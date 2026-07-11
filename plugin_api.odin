package main

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:thread"
import "core:sync"
import "core:time"

// Local plugin API — inspired by the *public* VTube Studio WebSocket API shape
// (apiName / messageType / data), but:
//   - binds to 127.0.0.1 only
//   - never contacts Steam or Denchi servers
//   - uses newline-delimited JSON over TCP (simple, easy to script)
//
// Connect:  tcp://127.0.0.1:8001
// Protocol: one JSON object per line, request → response

Plugin_API :: struct {
	enabled:     bool,
	port:        int,
	// shared state (protected by mutex)
	mutex:       sync.Mutex,
	// latest tracking + model params snapshot for readers
	track:       Tracking_Inputs,
	params:      map[string]f32,
	model_name:  string,
	// inject queue from plugins → applied next frame
	injects:     [dynamic]Param_Inject,
	// server
	listener:    net.TCP_Socket,
	running:     bool,
	th:          ^thread.Thread,
	instance_id: string,
}

Param_Inject :: struct {
	id:    string,
	value: f32,
	weight: f32, // 0..1 blend
}

API_Envelope :: struct {
	apiName:     string `json:"apiName"`,
	apiVersion:  string `json:"apiVersion"`,
	requestID:   string `json:"requestID"`,
	messageType: string `json:"messageType"`,
}

api_init :: proc(port: int, enabled: bool) -> ^Plugin_API {
	api := new(Plugin_API)
	api.enabled = enabled
	api.port = port
	api.params = make(map[string]f32)
	api.injects = make([dynamic]Param_Inject)
	api.model_name = "Default Procedural"
	api.instance_id = "odin-vtube-local"
	api.track = default_tracking()

	if !enabled {
		fmt.println("[api] disabled")
		return api
	}

	endpoint := net.Endpoint{
		address = net.IP4_Address{127, 0, 0, 1},
		port    = port,
	}
	sock, err := net.listen_tcp(endpoint)
	if err != nil {
		fmt.println("[api] listen failed on", port, ":", err, "— API off")
		api.enabled = false
		return api
	}
	api.listener = sock
	api.running = true
	api.th = thread.create_and_start_with_data(api, api_server_thread)
	fmt.println("[api] listening on 127.0.0.1:", port, "(localhost only)")
	return api
}

api_shutdown :: proc(api: ^Plugin_API) {
	if api == nil do return
	api.running = false
	if api.enabled {
		net.close(api.listener)
	}
	if api.th != nil {
		thread.join(api.th)
		thread.destroy(api.th)
	}
	sync.mutex_lock(&api.mutex)
	delete(api.params)
	delete(api.injects)
	destroy_tracking(&api.track)
	sync.mutex_unlock(&api.mutex)
	free(api)
}

// Main thread: push snapshot + pull injects
api_sync_from_app :: proc(api: ^Plugin_API, track: Tracking_Inputs, params: Model_Params, model_name: string) {
	if api == nil || !api.enabled do return
	sync.mutex_lock(&api.mutex)
	// copy key tracking fields (custom map shallow — injects are separate)
	api.track.FaceAngleX = track.FaceAngleX
	api.track.FaceAngleY = track.FaceAngleY
	api.track.FaceAngleZ = track.FaceAngleZ
	api.track.EyeOpenLeft = track.EyeOpenLeft
	api.track.EyeOpenRight = track.EyeOpenRight
	api.track.MouthOpen = track.MouthOpen
	api.track.MouthSmile = track.MouthSmile
	api.track.Breath = track.Breath
	api.model_name = model_name
	clear(&api.params)
	for k, v in params.values {
		api.params[k] = v
	}
	sync.mutex_unlock(&api.mutex)
}

api_apply_injects :: proc(api: ^Plugin_API, track: ^Tracking_Inputs, params: ^Model_Params) {
	if api == nil || !api.enabled do return
	sync.mutex_lock(&api.mutex)
	for inj in api.injects {
		// Prefer known tracking inputs; else model param / custom
		applied := false
		switch inj.id {
		case "FaceAngleX":
			track.FaceAngleX = lerp_f(track.FaceAngleX, inj.value, inj.weight)
			applied = true
		case "FaceAngleY":
			track.FaceAngleY = lerp_f(track.FaceAngleY, inj.value, inj.weight)
			applied = true
		case "FaceAngleZ":
			track.FaceAngleZ = lerp_f(track.FaceAngleZ, inj.value, inj.weight)
			applied = true
		case "MouthOpen":
			track.MouthOpen = lerp_f(track.MouthOpen, inj.value, inj.weight)
			applied = true
		case "MouthSmile":
			track.MouthSmile = lerp_f(track.MouthSmile, inj.value, inj.weight)
			applied = true
		case "EyeOpenLeft":
			track.EyeOpenLeft = lerp_f(track.EyeOpenLeft, inj.value, inj.weight)
			applied = true
		case "EyeOpenRight":
			track.EyeOpenRight = lerp_f(track.EyeOpenRight, inj.value, inj.weight)
			applied = true
		}
		if !applied {
			// model param or custom tracking
			if strings.has_prefix(inj.id, "Param") {
				cur := get_param(params^, inj.id)
				params.values[inj.id] = lerp_f(cur, inj.value, inj.weight)
			} else {
				track.custom[inj.id] = inj.value
			}
		}
	}
	clear(&api.injects)
	sync.mutex_unlock(&api.mutex)
}

api_server_thread :: proc(data: rawptr) {
	api := cast(^Plugin_API)data
	for api.running {
		client, source, err := net.accept_tcp(api.listener)
		if err != nil {
			if api.running {
				// brief pause on error
				time.sleep(50 * time.Millisecond)
			}
			continue
		}
		fmt.println("[api] client from", source)
		// handle client on this thread serially (simple; enough for local tools)
		api_handle_client(api, client)
		net.close(client)
	}
}

api_handle_client :: proc(api: ^Plugin_API, client: net.TCP_Socket) {
	buf: [8192]u8
	acc: strings.Builder
	strings.builder_init(&acc)
	defer strings.builder_destroy(&acc)

	for api.running {
		n, err := net.recv_tcp(client, buf[:])
		if err != nil || n <= 0 {
			break
		}
		strings.write_bytes(&acc, buf[:n])
		// process complete lines
		for {
			s := strings.to_string(acc)
			idx := strings.index_byte(s, '\n')
			if idx < 0 do break
			line := strings.trim_space(s[:idx])
			rest := s[idx + 1:]
			// rebuild builder with rest
			strings.builder_reset(&acc)
			strings.write_string(&acc, rest)
			if len(line) == 0 do continue
			resp := api_process_line(api, line)
			resp_nl := fmt.tprintf("%s\n", resp)
			net.send_tcp(client, transmute([]u8)resp_nl)
			// resp may be on temp allocator from tprintf — ok within frame of loop
		}
	}
}

api_process_line :: proc(api: ^Plugin_API, line: string) -> string {
	// Parse loosely
	env: API_Envelope
	if err := json.unmarshal_string(line, &env); err != nil {
		return api_error_json("bad_json", fmt.tprint(err))
	}

	req_id := env.requestID if env.requestID != "" else "none"
	msg := env.messageType

	switch msg {
	case "APIStateRequest":
		return api_ok(req_id, "APIStateResponse", fmt.tprintf(
			`{{"active":true,"vTubeStudioVersion":"OdinVTube-0.1","currentSessionAuthenticated":true,"instanceID":"%s"}}`,
			api.instance_id,
		))
	case "StatisticsRequest":
		return api_ok(req_id, "StatisticsResponse", fmt.tprintf(
			`{{"uptime":0,"framerate":60,"vTubeStudioVersion":"OdinVTube-0.1","allowedPlugins":99,"connectedPlugins":1,"startedWithSteam":false,"windowTitle":"OdinVTube"}}`,
		))
	case "AuthenticationTokenRequest", "AuthenticationRequest":
		// always approve local plugins
		return api_ok(req_id, "AuthenticationResponse", `{"authenticated":true,"reason":"local-only auto approve"}`)
	case "InputParameterListRequest":
		return api_ok(req_id, "InputParameterListResponse", api_build_input_list(api))
	case "Live2DParameterListRequest":
		return api_ok(req_id, "Live2DParameterListResponse", api_build_live2d_list(api))
	case "InjectParameterDataRequest":
		api_queue_injects(api, line)
		return api_ok(req_id, "InjectParameterDataResponse", `{}`)
	case "CurrentModelRequest":
		sync.mutex_lock(&api.mutex)
		name := api.model_name
		sync.mutex_unlock(&api.mutex)
		return api_ok(req_id, "CurrentModelResponse", fmt.tprintf(
			`{{"modelLoaded":true,"modelName":"%s","modelID":"local","vtsModelName":"%s"}}`,
			name, name,
		))
	case "HotkeyListRequest":
		return api_ok(req_id, "HotkeyListResponse", `{"availableHotkeys":[{"name":"Happy","hotkeyID":"expr_happy"},{"name":"Angry","hotkeyID":"expr_angry"},{"name":"Sad","hotkeyID":"expr_sad"},{"name":"Shock","hotkeyID":"expr_shock"}]}`)
	case:
		return api_error_json(req_id, fmt.tprintf("unknown messageType: %s", msg))
	}
}

api_ok :: proc(req_id, msg_type, data_json: string) -> string {
	return fmt.tprintf(
		`{{"apiName":"OdinVTubeLocalAPI","apiVersion":"1.0","requestID":"%s","messageType":"%s","data":%s}}`,
		req_id, msg_type, data_json,
	)
}

api_error_json :: proc(req_id, reason: string) -> string {
	return fmt.tprintf(
		`{{"apiName":"OdinVTubeLocalAPI","apiVersion":"1.0","requestID":"%s","messageType":"APIError","data":{{"errorID":1,"message":"%s"}}}}`,
		req_id, reason,
	)
}

api_build_input_list :: proc(api: ^Plugin_API) -> string {
	sync.mutex_lock(&api.mutex)
	defer sync.mutex_unlock(&api.mutex)
	t := api.track
	// default tracking inputs
	return fmt.tprintf(
		`{{"modelLoaded":true,"defaultParameters":[` +
		`{{"name":"FaceAngleX","value":%.3f,"min":-30,"max":30,"defaultValue":0}},` +
		`{{"name":"FaceAngleY","value":%.3f,"min":-30,"max":30,"defaultValue":0}},` +
		`{{"name":"FaceAngleZ","value":%.3f,"min":-30,"max":30,"defaultValue":0}},` +
		`{{"name":"MouthOpen","value":%.3f,"min":0,"max":1,"defaultValue":0}},` +
		`{{"name":"MouthSmile","value":%.3f,"min":0,"max":1,"defaultValue":0}},` +
		`{{"name":"EyeOpenLeft","value":%.3f,"min":0,"max":1,"defaultValue":1}},` +
		`{{"name":"EyeOpenRight","value":%.3f,"min":0,"max":1,"defaultValue":1}},` +
		`{{"name":"Breath","value":%.3f,"min":0,"max":1,"defaultValue":0.5}}` +
		`],"customParameters":[]}}`,
		t.FaceAngleX, t.FaceAngleY, t.FaceAngleZ,
		t.MouthOpen, t.MouthSmile, t.EyeOpenLeft, t.EyeOpenRight, t.Breath,
	)
}

api_build_live2d_list :: proc(api: ^Plugin_API) -> string {
	sync.mutex_lock(&api.mutex)
	defer sync.mutex_unlock(&api.mutex)
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)
	strings.write_string(&b, `{"modelLoaded":true,"parameters":[`)
	first := true
	for k, v in api.params {
		if !first do strings.write_byte(&b, ',')
		first = false
		strings.write_string(&b, fmt.tprintf(`{{"name":"%s","value":%.4f}}`, k, v))
	}
	strings.write_string(&b, `]}`)
	return strings.clone(strings.to_string(b), context.temp_allocator)
}

// Minimal inject parse: find "parameterValues" array entries with id + value
api_queue_injects :: proc(api: ^Plugin_API, line: string) {
	// Very small hand parser for {"id":"X","value":N} pairs inside parameterValues
	// Prefer full json if structure matches common VTS inject shape.
	Inject_File :: struct {
		data: struct {
			parameterValues: []struct {
				id:     string,
				value:  f32,
				weight: f32,
			},
		},
	}
	parsed: Inject_File
	if err := json.unmarshal_string(line, &parsed); err != nil {
		fmt.println("[api] inject parse fail:", err)
		return
	}
	sync.mutex_lock(&api.mutex)
	for p in parsed.data.parameterValues {
		w := p.weight > 0 ? p.weight : 1
		append(&api.injects, Param_Inject{id = strings.clone(p.id), value = p.value, weight = w})
	}
	sync.mutex_unlock(&api.mutex)
}

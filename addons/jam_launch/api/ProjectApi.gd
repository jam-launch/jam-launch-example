@tool
extends HttpBase
class_name ProjectApi

func create_project(project_name: String) -> Result:
	return await _json_http(
		"/projects",
		HTTPClient.METHOD_POST,
		{"project_name": project_name}
	)

func list_projects() -> Result:
	return await _json_http("/projects")

func get_project(project_id: String) -> Result:
	return await _json_http("/projects/%s" % project_id)

func delete_project(project_id: String) -> Result:
	return await _json_http(
		"/projects/%s" % project_id,
		HTTPClient.METHOD_DELETE
	)

func build_project(project_id: String, project_dir: EditorFileSystemDirectory) -> Result:
	print("getting upload info...")
	var pre_res = await _json_http(
		"/projects/%s/releases" % project_id,
		HTTPClient.METHOD_POST,
		{}
	)
	if pre_res.errored:
		return pre_res
		
	var project_bytes = ProjectPacker.pack(project_dir)
	if project_bytes is String:
		var res = Result.new()
		res.errored = true
		res.error_msg = project_bytes
		return res
	
	var upload_body = PackedByteArray()
	upload_body.append_array("------BodyBoundary1234\r\n".to_utf8_buffer())
	var fields = pre_res.data["upload_target"]["fields"]
	for key in fields:
		upload_body.append_array(("Content-Disposition: form-data; name=\"%s\"\r\n\r\n" % key).to_utf8_buffer())
		upload_body.append_array(("%s" % fields[key]).to_utf8_buffer())
		upload_body.append_array("\r\n------BodyBoundary1234\r\n".to_utf8_buffer())
	
	upload_body.append_array(("Content-Disposition: form-data; name=\"file\"; filename=\"project.zip\"\r\n").to_utf8_buffer())
	upload_body.append_array(("Content-Type: application/zip\r\n\r\n").to_utf8_buffer())
	upload_body.append_array(project_bytes)
	upload_body.append_array("\r\n------BodyBoundary1234--\r\n".to_utf8_buffer())
	
	var h = pool.get_client()
	print("uploading project...")
	var upload_err = h.http.request_raw(
		pre_res.data["upload_target"]["url"],
		["Content-Type: multipart/form-data; boundary=----BodyBoundary1234"],
		HTTPClient.METHOD_POST,
		upload_body
	)
	
	var result = Result.new()
	if upload_err != OK:
		result.errored = true
		result.error_msg = "HTTP request error for upload"
		return result
		
	var resp = await h.http.request_completed
	var response_code = resp[1]
	if response_code > 299:
		result.errored = true
		result.error_msg = "HTTP error %d for upload" % response_code
		return result
	
	print("build submitted!")
	return pre_res

func update_release(project_id: String, release_id: String, props: Dictionary) -> Result:
	return await _json_http(
		"/projects/%s/releases/%s" % [project_id, release_id],
		HTTPClient.METHOD_POST,
		props
	)

func post_config(project_id: String, cfg: Dictionary) -> Result:
	return await _json_http(
		"/projects/%s/config" % project_id,
		HTTPClient.METHOD_POST,
		cfg
	)

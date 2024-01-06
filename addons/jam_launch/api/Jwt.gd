extends RefCounted
class_name Jwt

signal token_changed(String)

class TokenData:
	extends RefCounted
	var header: Dictionary
	var claims: Dictionary
	var signature: String
	
class TokenParseResult:
	extends RefCounted
	var error: String = ""
	var errored: bool = false
	var data: TokenData

var jwt_token: String = ""

func set_token(jwt: String) -> TokenParseResult:
	var result = Jwt.parse_token(jwt)
	if result.errored:
		return result
	jwt_token = jwt
	token_changed.emit(jwt_token)
	return result

func get_token() -> String:
	return jwt_token

func clear():
	jwt_token = ""
	token_changed.emit("")

func has_token() -> bool:
	return len(jwt_token) > 0

static func b64url_to_b64(b64_url: String) -> String:
	var b64 = b64_url
	b64 = b64.replace("-", "+")
	b64 = b64.replace("_", "/")
	var overhang = len(b64) % 4
	if overhang != 0:
		for i in range(4 - overhang):
			b64 += "="
	return b64

static func parse_token(token: String) -> TokenParseResult:
	var result = TokenParseResult.new()
	var parts := token.split(".")
	if len(parts) != 3:
		result.errored = true
		result.error = "Invalid JWT token format"
		return result
	
	var tkn = TokenData.new()
	
	var header_b64 := b64url_to_b64(parts[0])
	var header_json := Marshalls.base64_to_utf8(header_b64)
	tkn.header = JSON.parse_string(header_json)
	if not tkn.header:
		result.errored = true
		result.error = "Failed to parse JWT header"
		return result
	
	var claims_b64 := b64url_to_b64(parts[1])
	var claims_json := Marshalls.base64_to_utf8(claims_b64)
	tkn.claims = JSON.parse_string(claims_json)
	if not tkn.claims:
		result.errored = true
		result.error = "Failed to parse JWT claims"
		return result
	
	var sig_b64 := b64url_to_b64(parts[2])
	var raw_sig := Marshalls.base64_to_raw(sig_b64)
	if not raw_sig or raw_sig.is_empty():
		result.errored = true
		result.error = "Failed to parse JWT signature"
		return result
		
	tkn.signature = parts[2]
	
	result.data = tkn
	return result

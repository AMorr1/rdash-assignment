import unittest

try:
    import jwt
    from rdash_common.auth import mint_service_token, verify_bearer_token
except ModuleNotFoundError:  # pragma: no cover - depends on local env
    jwt = None
    mint_service_token = None
    verify_bearer_token = None


@unittest.skipUnless(jwt is not None, "PyJWT and app dependencies are not installed")
class AuthTests(unittest.TestCase):
    def test_mint_and_verify_service_token(self):
        secret = "test-secret"
        token = mint_service_token(secret, "issuer", "audience", ttl_seconds=300)
        claims = verify_bearer_token(
            f"Bearer {token}",
            secret=secret,
            audience="audience",
            issuer="issuer",
        )
        self.assertEqual(claims["iss"], "issuer")
        self.assertEqual(claims["aud"], "audience")
        self.assertEqual(claims["scope"], "registry.read")

    def test_token_is_hs256(self):
        token = mint_service_token("secret", "issuer", "aud")
        header = jwt.get_unverified_header(token)
        self.assertEqual(header["alg"], "HS256")


if __name__ == "__main__":
    unittest.main()

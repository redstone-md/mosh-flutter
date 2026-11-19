// Signs the JWTs both push services take as credentials: ES256 provider
// tokens for APNs, RS256 assertions for Google's OAuth. WebCrypto only.

export type JwtAlgorithm = "ES256" | "RS256";

const KEYS: Record<JwtAlgorithm, { key: EcKeyImportParams | RsaHashedImportParams; sign: AlgorithmIdentifier | EcdsaParams }> = {
  ES256: { key: { name: "ECDSA", namedCurve: "P-256" }, sign: { name: "ECDSA", hash: "SHA-256" } },
  RS256: { key: { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, sign: { name: "RSASSA-PKCS1-v1_5" } },
};

/** `header.claims.signature`, signed with the PKCS#8 PEM `pem`; `alg` goes into the header. */
export async function signJwt(
  algorithm: JwtAlgorithm, header: object, claims: object, pem: string,
): Promise<string> {
  const encode = (value: object) => base64url(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned = `${encode({ alg: algorithm, ...header })}.${encode(claims)}`;
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, "")), (c) => c.charCodeAt(0));
  const { key, sign } = KEYS[algorithm];
  const signingKey = await crypto.subtle.importKey("pkcs8", der, key, false, ["sign"]);
  const signature = await crypto.subtle.sign(sign, signingKey, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64url(new Uint8Array(signature))}`;
}

export function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

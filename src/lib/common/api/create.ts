import { apiPost } from './base';
import {
	type ApiApiKey,
	type ApiNode,
	type ApiPreAuthKey,
	type ApiUser,
	type Node,
	type User,
} from '$lib/common/types';
import { debug } from '$lib/common/debug';
import { API_URL_APIKEY, API_URL_AUTH, API_URL_NODE, API_URL_PREAUTHKEY, API_URL_USER } from './url';

// grpc-gateway answers unknown routes with HTTP 404 and the message "Not Found".
// Used to fall back to legacy endpoints on headscale versions before 0.29.
function isRouteNotFound(err: unknown): boolean {
	return err instanceof Error && err.message.trim().toLowerCase() === 'not found';
}

export async function createApiKey() {
	// create 90-day API Key
	const date = new Date();
	date.setDate(date.getDate() + 90);
	const data = { expiration: date.toISOString() };
	const { apiKey } = await apiPost<ApiApiKey>(API_URL_APIKEY, data);
	debug('Created API Key "...' + apiKey.slice(-10) + '"')
	return apiKey;
}

export async function createUser(username: string): Promise<User> {
	if (username.length === 0) {
		throw new Error("Username cannot be empty")
	}
	const data = { name: username };
	const { user } = await apiPost<ApiUser>(API_URL_USER, data);
	debug('Created user "' + username + '"');
	return user;
}

// Accepts the bare auth ID, or anything containing it, such as the
// "headscale auth register --auth-id <id>" command or the /register/<id> URL
// shown to the client.
export function normalizeAuthId(key: string): string {
	key = key.trim();
	const fromFlag = key.match(/--(?:auth-id|key)[ =](\S+)/);
	if (fromFlag) {
		return fromFlag[1];
	}
	const fromUrl = key.match(/\/register\/([^/?#\s]+)/);
	if (fromUrl) {
		return fromUrl[1];
	}
	return key;
}

export async function createNode(key: string, username: string): Promise<Node> {
	const authId = normalizeAuthId(key);
	let node: Node;
	try {
		// headscale >= 0.29: POST /api/v1/auth/register
		({ node } = await apiPost<ApiNode>(API_URL_AUTH + '/register', { user: username, authId }));
	} catch (err) {
		if (!isRouteNotFound(err)) {
			throw err;
		}
		// headscale < 0.29 (deprecated since 0.29)
		const params = new URLSearchParams({ user: username, key: authId });
		({ node } = await apiPost<ApiNode>(API_URL_NODE + '/register?' + params));
	}
	debug('Created Node "' + node.givenName + '" for user "' + username + '"');
	return node;
}

export async function createPreAuthKey(
	user: User,
	ephemeral: boolean,
	reusable: boolean,
	expiration: Date | string,
	aclTags: string[] = [],
) {
	const data = {
		user: user.id,
		reusable,
		ephemeral,
		expiration: new Date(expiration).toISOString(),
		...(aclTags.length > 0
			? { aclTags: aclTags.map((t) => (t.startsWith('tag:') ? t : 'tag:' + t)) }
			: {}),
	};
	const { preAuthKey } = await apiPost<ApiPreAuthKey>(API_URL_PREAUTHKEY, data);
	debug('Created PreAuthKey for user "' + user.name + '"');
	return preAuthKey;
}

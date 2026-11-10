import { beforeEach, describe, expect, it, vi } from 'vitest';

const apiPost = vi.fn();
vi.mock('./base', () => ({ apiPost: (...args: unknown[]) => apiPost(...args) }));
vi.mock('$lib/common/debug', () => ({ debug: vi.fn() }));

import { createNode, createPreAuthKey, normalizeAuthId } from './create';

const node = { id: '1', givenName: 'laptop' };

describe('normalizeAuthId', () => {
	it.each([
		['abc123', 'abc123'],
		['  abc123  ', 'abc123'],
		['headscale auth register --auth-id abc123 --user alice', 'abc123'],
		['headscale nodes register --key abc123 --user alice', 'abc123'],
		['https://hs.example.com/register/abc123', 'abc123'],
	])('%s -> %s', (input, expected) => {
		expect(normalizeAuthId(input)).toBe(expected);
	});
});

describe('createNode', () => {
	beforeEach(() => apiPost.mockReset());

	it('uses POST /api/v1/auth/register with a JSON body (headscale 0.29)', async () => {
		apiPost.mockResolvedValueOnce({ node });
		await createNode('https://hs.example.com/register/abc123', 'alice');
		expect(apiPost).toHaveBeenCalledTimes(1);
		expect(apiPost).toHaveBeenCalledWith('/api/v1/auth/register', { user: 'alice', authId: 'abc123' });
	});

	it('falls back to the legacy endpoint when the route does not exist', async () => {
		apiPost.mockRejectedValueOnce(new Error('Not Found')).mockResolvedValueOnce({ node });
		await createNode('abc123', 'alice');
		expect(apiPost).toHaveBeenLastCalledWith('/api/v1/node/register?user=alice&key=abc123');
	});

	it('does not fall back on real errors', async () => {
		apiPost.mockRejectedValueOnce(new Error('looking up user: record not found'));
		await expect(createNode('abc123', 'alice')).rejects.toThrow('record not found');
		expect(apiPost).toHaveBeenCalledTimes(1);
	});
});

describe('createPreAuthKey', () => {
	beforeEach(() => apiPost.mockReset());

	it('sends aclTags with tag: prefix', async () => {
		apiPost.mockResolvedValueOnce({ preAuthKey: { key: 'k' } });
		await createPreAuthKey({ id: '7', name: 'alice' } as never, false, true, '2030-01-01T00:00:00Z', ['server', 'tag:nas']);
		expect(apiPost.mock.calls[0][1]).toMatchObject({ user: '7', aclTags: ['tag:server', 'tag:nas'] });
	});

	it('omits aclTags when none are given', async () => {
		apiPost.mockResolvedValueOnce({ preAuthKey: { key: 'k' } });
		await createPreAuthKey({ id: '7', name: 'alice' } as never, false, true, '2030-01-01T00:00:00Z');
		expect(apiPost.mock.calls[0][1]).not.toHaveProperty('aclTags');
	});
});

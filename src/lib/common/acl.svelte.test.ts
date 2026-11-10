import { describe, expect, it, vi } from 'vitest';

// acl.svelte.ts imports the API layer (for saveConfig); stub it so no app state is loaded
vi.mock('./api', () => ({ setPolicy: vi.fn() }));
vi.mock('./debug', () => ({ debug: vi.fn() }));
vi.mock('$lib/common/funcs', () => ({
	isValidCIDR: () => true,
	isValidIP: () => true,
	toastError: vi.fn(),
	toastSuccess: vi.fn(),
}));

import { ACLBuilder } from './acl.svelte';

const policy029 = `{
	// headscale 0.29 policy with fields the editor does not manage
	"groups": { "group:admins": ["alice@"] },
	"tagOwners": { "tag:server": ["group:admins"] },
	"hosts": {},
	"acls": [
		{ "#ha-meta": { "name": "allow all", "open": true }, "action": "accept", "src": ["*"], "dst": ["*:*"] },
	],
	"ssh": [
		{
			"action": "check",
			"src": ["group:admins"],
			"dst": ["tag:server"],
			"users": ["root"],
			"checkPeriod": "1h",
			"acceptEnv": ["GIT_*"],
		},
	],
	"grants": [{ "src": ["*"], "dst": ["*"], "ip": ["*"] }],
	"nodeAttrs": [{ "target": ["*"], "attr": ["funnel"] }],
	"randomizeClientPort": true,
}`;

describe('ACLBuilder round-trip (headscale 0.29)', () => {
	it('keeps checkPeriod/acceptEnv when an SSH rule is edited', () => {
		const acl = ACLBuilder.fromPolicy(policy029);
		const rule = acl.getSshRule(0);
		acl.setSshRule(0, { action: rule.action, src: [...rule.src, 'alice@'], dst: rule.dst, users: rule.users });

		const out = JSON.parse(acl.JSON());
		expect(out.ssh[0]).toEqual({
			action: 'check',
			src: ['group:admins', 'alice@'],
			dst: ['tag:server'],
			users: ['root'],
			checkPeriod: '1h',
			acceptEnv: ['GIT_*'],
		});
	});

	it('drops checkPeriod when switching to accept', () => {
		const acl = ACLBuilder.fromPolicy(policy029);
		acl.setSshRuleAction(0, 'accept');
		const out = JSON.parse(acl.JSON());
		expect(out.ssh[0].action).toBe('accept');
		expect(out.ssh[0].checkPeriod).toBeUndefined();
		expect(out.ssh[0].acceptEnv).toEqual(['GIT_*']);
	});

	it('keeps #ha-meta when an ACL rule is edited', () => {
		const acl = ACLBuilder.fromPolicy(policy029);
		const p = acl.getPolicy(0);
		acl.setPolicy(0, { action: p.action, proto: 'tcp', src: p.src, dst: p.dst });
		const out = JSON.parse(acl.JSON());
		expect(out.acls[0]['#ha-meta']).toEqual({ name: 'allow all', open: true });
		expect(out.acls[0].proto).toBe('tcp');
	});

	it('passes grants, nodeAttrs and randomizeClientPort through unchanged', () => {
		const out = JSON.parse(ACLBuilder.fromPolicy(policy029).JSON());
		expect(out.grants).toEqual([{ src: ['*'], dst: ['*'], ip: ['*'] }]);
		expect(out.nodeAttrs).toEqual([{ target: ['*'], attr: ['funnel'] }]);
		expect(out.randomizeClientPort).toBe(true);
	});
});

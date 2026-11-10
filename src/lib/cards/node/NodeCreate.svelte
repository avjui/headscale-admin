<script lang="ts">
	import { approveAuth, createNode, rejectAuth } from '$lib/common/api';
	import { debug } from '$lib/common/debug';
	import { toastError, toastSuccess, focus } from '$lib/common/funcs';
	import { getToastStore } from '@skeletonlabs/skeleton';

	import RawMdiCheckCircleOutline from '~icons/mdi/check-circle-outline';

	import { App } from '$lib/States.svelte';

	type NodeCreateProps = {
		show: boolean,
	}

	let { show = $bindable(false) }: NodeCreateProps = $props()

	// register: assign a pending node registration to a user
	// approve/reject: answer a pending auth session (e.g. SSH "check"), headscale >= 0.29
	type Mode = 'register' | 'approve' | 'reject';

	let mode = $state<Mode>('register');
	let nodekey = $state('');
	let username = $state('');
	let loading = $state(false);
	const ToastStore = getToastStore();

	async function submit(e?: Event) {
		e?.preventDefault();
		if (mode === 'register') {
			await newNode();
		} else {
			await answerAuth(mode);
		}
	}

	async function newNode() {
		if (nodekey == '' || username == '') {
			toastError('Username and Auth ID are Required', ToastStore);
			return;
		}
		loading = true;
		try {
			// create the node
			const n = await createNode(nodekey, username);

			// append to the store
			App.nodes.value.push(n)

			// success message
			toastSuccess('Created node "' + n.name + '"', ToastStore);

			// no longer needed
			show = false;
			nodekey = '';
			username = '';
		} catch (error) {
			if (error instanceof Error) {
				debug(error);
				toastError('Failed to create node', ToastStore, error);
			}
		} finally {
			loading = false;
		}
	}

	async function answerAuth(verdict: 'approve' | 'reject') {
		if (nodekey == '') {
			toastError('Auth ID is Required', ToastStore);
			return;
		}
		loading = true;
		try {
			if (verdict === 'approve') {
				await approveAuth(nodekey);
				toastSuccess('Approved auth request', ToastStore);
			} else {
				await rejectAuth(nodekey);
				toastSuccess('Rejected auth request', ToastStore);
			}
			show = false;
			nodekey = '';
		} catch (error) {
			if (error instanceof Error) {
				debug(error);
				toastError(`Failed to ${verdict} auth request`, ToastStore, error);
			}
		} finally {
			loading = false;
		}
	}
</script>

<div class="flex w-full">
	<form onsubmit={submit} class="w-full flex flex-row space-x-4">
		<select
			class="select rounded-md w-auto"
			bind:value={mode}
			disabled={loading}
			title="Register a node, or approve/reject a pending auth request (headscale 0.29+)"
		>
			<option value="register">Register</option>
			<option value="approve">Approve</option>
			<option value="reject">Reject</option>
		</select>
		<input
			class="input rounded-md w-full md:w-1/2 lg:w-1/3"
			type="text"
			placeholder="Auth ID, register URL or command..."
			disabled={loading}
			bind:value={nodekey}
			use:focus
		/>
		{#if mode === 'register'}
		<select class="select rounded-md w-full md:w-1/2 lg:w-1/3" bind:value={username} disabled={loading}>
			<option value="" disabled>Select user</option>
			{#each App.users.value as user}
				<option value={user.name}>{user.name} (ID: {user.id})</option>
			{/each}
		</select>
		{/if}
		<button type="submit" class="btn btn-icon" disabled={loading}>
			<RawMdiCheckCircleOutline />
		</button>
	</form>
</div>

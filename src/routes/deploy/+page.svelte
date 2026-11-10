<script lang="ts">
	import {
		copyToClipboard,
		isValidCIDR,
		isValidTag,
		toastError,
		toastSuccess,
	} from '$lib/common/funcs';
	import DeployCheck from './DeployCheck.svelte';
	import Page from '$lib/page/Page.svelte';
	import PageHeader from '$lib/page/PageHeader.svelte';
	import type { Deployment, User } from '$lib/common/types';
	import { InputChip, getToastStore } from '@skeletonlabs/skeleton';
	import { page } from '$app/state';
	import { createPreAuthKey } from '$lib/common/api';
	import { App } from '$lib/States.svelte';

	let deployment: Deployment = $state(App.deploymentDefaults.value);
	let preAuthKeyLoading = $state(false);
	let preAuthKeySettings = $state(defaultPreAuthKeySettings());
	const ToastStore = getToastStore();

	function defaultExpires(hours: number = 1, minutes: number = 0) {
		const tzOffset = new Date().getTimezoneOffset() * 60 * 1000;
		return new Date(Date.now() - tzOffset + minutes * 60 * 1000 + hours * 60 * 60 * 1000)
			.toISOString()
			.split(':')
			.slice(0, 2)
			.join(':');
	}

	function defaultPreAuthKeySettings() {
		return {
			ephemeral: false,
			reusable: false,
			expiration: defaultExpires(),
			aclTags: [] as string[],
		};
	}

	function selectedPreAuthUser(): User | undefined {
		return App.users.value.find((user) => user.id === deployment.preAuthKeyUser);
	}

	async function generatePreAuthKey() {
		const user = selectedPreAuthUser();
		if (!user) {
			return;
		}

		preAuthKeyLoading = true;
		try {
			const preAuthKey = await createPreAuthKey(
				user,
				preAuthKeySettings.ephemeral,
				preAuthKeySettings.reusable,
				preAuthKeySettings.expiration,
				preAuthKeySettings.aclTags,
			);
			deployment.preAuthKey = preAuthKey.key;
			toastSuccess('PreAuth Key created. Copy it now, it can only be viewed once.', ToastStore);
		} catch (e) {
			toastError('Failed to create PreAuth Key: ' + e, ToastStore);
		} finally {
			preAuthKeyLoading = false;
		}
	}

	$effect(() => {
		if (deployment.preAuthKeyUser === '') {
			deployment.preAuthKey = '';
		}
	});

	let craftCommand = (d: Deployment) => {
		const cmd = ['tailscale up --login-server=' + (App.apiUrl.value || page.url.origin)];

		// general
		d.shieldsUp && cmd.push('--shields-up');
		d.generateQR && cmd.push('--qr');
		d.reset && cmd.push('--reset');
		d.forceReauth && cmd.push('--force-reauth');
		d.sshServer && cmd.push('--ssh');
		d.usePreAuthKey && d.preAuthKey !== '' && cmd.push('--auth-key=' + d.preAuthKey);
		d.unattended && cmd.push('--unattended')
		d.operator && d.operatorValue != '' && cmd.push('--operator=' + d.operatorValue);
		d.customHostname && d.customHostnameValue != '' && cmd.push('--hostname=' + d.customHostnameValue)

		// advertise
		d.advertiseExitNode && cmd.push('--advertise-exit-node');
		d.advertiseExitNodeLocalAccess &&
			cmd.push('--exit-node-allow-lan-access');
		d.advertiseRoutes &&
			d.advertiseRoutesValues.length > 0 &&
			cmd.push('--advertise-routes=' + d.advertiseRoutesValues.join(','));
		d.advertiseTags &&
			d.advertiseTagsValues.length > 0 &&
			cmd.push(
				'--advertise-tags=' +
					d.advertiseTagsValues.map((s) => (s.startsWith('tag:') ? s : 'tag:' + s)).join(','),
			);

		// accept
		d.acceptDns ? cmd.push('--accept-dns') : cmd.push('--accept-dns=false');
		d.acceptRoutes && cmd.push('--accept-routes');
		d.acceptExitNode && d.acceptExitNodeValue && cmd.push('--exit-node=' + d.acceptExitNodeValue);
		return cmd.join(' ');
	};
</script>

<Page>
	<PageHeader title="Deploy" buttonText={''} show={true}>
		{#snippet button()}
			<button
				class="bg-gray-400/30 dark:bg-gray-800/70 border border-dashed border-slate-200 border-1 pr-0 pl-4 rounded-lg justify-start text-left w-[90%]"
				onclick={() =>
					copyToClipboard(craftCommand(deployment), ToastStore, 'Copied Command to Clipboard!')}
				><code class="text-black dark:text-white text-sm block py-4 w-full"
					>{craftCommand(deployment)}</code
				>
			</button>
		{/snippet}
	</PageHeader>

	<div class="grid grid-cols-12">
		<p class="text-xl col-span-12">General:</p>
		<DeployCheck
			bind:checked={deployment.shieldsUp}
			name="Shields Up"
			help="Block incoming connections"
		/>
		<DeployCheck
			bind:checked={deployment.generateQR}
			name="Generate QR Code"
			help="Create a scannable QR code to import into TailScale client"
		/>
		<DeployCheck
			bind:checked={deployment.reset}
			name="Reset"
			help="Reset unspecified settings to default values"
		/>
		<DeployCheck
			bind:checked={deployment.forceReauth}
			name="Force Reauthentication"
			help="Force user to re-authenticate to Headscale server"
		/>
		<DeployCheck
			bind:checked={deployment.sshServer}
			name="SSH Server"
			help="Run a local SSH server accessible by administrators"
		/>
		<DeployCheck
			bind:checked={deployment.unattended}
			name="Unattended"
			help="Run the tailscale client in unattended mode (on startup)"
		/>
		<DeployCheck 
			bind:checked={deployment.advertiseExitNodeLocalAccess}
			name="Allow LAN Access"
			help="Allow local network access while connected to the TailNet and using an exit node"
		/>
		<DeployCheck
			bind:checked={deployment.operator}
			name="Operator"
			help="(Unix Only) Run as a different user"
		>
			<input type="text" class="input text-sm rounded-md" bind:value={deployment.operatorValue} />
		</DeployCheck>
		<DeployCheck 
			bind:checked={deployment.customHostname}
			name="Custom Hostname"
			help="Set a custom hostname for the node"
		>
			<input type="text" class="input text-sm rounded-md" bind:value={deployment.customHostnameValue} />
		</DeployCheck>

		<p class="text-xl col-span-12"></p>
		<DeployCheck
			bind:checked={deployment.usePreAuthKey}
			name="PreAuth Key"
			help="A generated key to automatically authenticate the node for a given user"
		>
			<div class="flex flex-col gap-3">
				<select onchange={() => {deployment.preAuthKey = ''}} bind:value={deployment.preAuthKeyUser} class="input rounded-md">
					<option value="">Select user</option>
					{#each App.users.value as user}
						<option value={user.id}>{user.name}</option>
					{/each}
				</select>
				{#if deployment.preAuthKeyUser}
					<div class="grid grid-cols-1 md:grid-cols-2 gap-3">
						<div>
							<label class="label flex flex-col gap-2">
								<span>Expiration</span>
								<input
									type="datetime-local"
									class="input rounded-md w-full"
									bind:value={preAuthKeySettings.expiration}
								/>
							</label>
						</div>
						<div class="grid gap-2">
							<label class="flex items-center space-x-2">
								<input
									type="checkbox"
									class="checkbox"
									bind:checked={preAuthKeySettings.ephemeral}
								/>
								<span>Ephemeral</span>
							</label>
							<label class="flex items-center space-x-2">
								<input
									type="checkbox"
									class="checkbox"
									bind:checked={preAuthKeySettings.reusable}
								/>
								<span>Reusable</span>
							</label>
						</div>
						<div class="md:col-span-2">
							<label class="label flex flex-col gap-2">
								<span>Tags (optional; nodes joining with this key are owned by these tags)</span>
								<InputChip
									name="preAuthKeyAclTags"
									bind:value={preAuthKeySettings.aclTags}
									validation={isValidTag}
									on:invalid={() => {
										toastError('Tag should be a lowercase alphanumeric word', ToastStore);
									}}
								/>
							</label>
						</div>
					</div>
					<div class="flex flex-row flex-wrap gap-2">
						<button
							class="btn btn-sm rounded-md variant-filled-success"
							disabled={preAuthKeyLoading}
							onclick={generatePreAuthKey}
						>
							Generate PreAuth Key
						</button>
						{#if deployment.preAuthKey}
							<button
								class="btn btn-sm rounded-md variant-filled-secondary"
								onclick={() => copyToClipboard(deployment.preAuthKey, ToastStore)}
							>
								Copy Key
							</button>
						{/if}
					</div>
					{#if deployment.preAuthKey}
						<p class="text-xs text-slate-600 dark:text-slate-300">This key can only be viewed once. Copy it now.</p>
					{/if}
				{/if}
			</div>
		</DeployCheck>

		<p class="text-xl col-span-12 py-4">Advertise:</p>
		<DeployCheck
			bind:checked={deployment.advertiseExitNode}
			name="Advertise Exit Node"
			help="Allow other nodes on the TailNet to use this node as a gateway"
		/>
		<DeployCheck
			bind:checked={deployment.advertiseTags}
			name="Advertise Tags"
			help="List of advertised tags to apply to a machine on provisioning"
		>
			<InputChip
				name="advertiseRoutesValues"
				bind:value={deployment.advertiseTagsValues}
				validation={isValidTag}
				on:invalid={() => {
					toastError('Tag should be a lowercase alphanumeric word', ToastStore);
				}}
			/>
		</DeployCheck>
		<DeployCheck
			bind:checked={deployment.advertiseRoutes}
			name="Advertise Routes"
			help="List of subnets which are reachable via this node"
		>
			<InputChip
				name="advertiseRoutesValues"
				bind:value={deployment.advertiseRoutesValues}
				validation={isValidCIDR}
				on:invalid={() => {
					toastError('Invalid CIDR Format', ToastStore);
				}}
			/>
		</DeployCheck>

		<p class="text-xl col-span-12 py-4">Accept:</p>
		<DeployCheck
			bind:checked={deployment.acceptDns}
			name="Accept DNS"
			help="Accept the HeadScale-provided DNS settings"
		/>
		<DeployCheck
			bind:checked={deployment.acceptRoutes}
			name="Accept Routes"
			help="Accept other nodes' advertised subnets"
		/>
		<DeployCheck
			bind:checked={deployment.acceptExitNode}
			name="Exit Node"
			help="Use this node as a gateway (target node must advertise exit node)"
		>
			<label class="label">
				<select class="select" bind:value={deployment.acceptExitNodeValue}>
					{#each App.nodes.value as node}
						<option value={node.ipAddresses.filter((s) => /^\d+\.\d+\.\d+\.\d+$/.test(s))[0]}
							>{node.givenName} ({node.name})</option
						>
					{/each}
				</select>
			</label>
		</DeployCheck>
	</div>
		<button class="btn rounded-md variant-filled-secondary mt-4" onclick={() => {
			App.saveDeploymentDefaults(deployment)
			toastSuccess('Saved Deployment Defaults', ToastStore)
		}}>
			Save Defaults
		</button>
</Page>

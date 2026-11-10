<script lang="ts">
	import CardListEntry from '../CardListEntry.svelte';
	import Delete from '$lib/parts/Delete.svelte';
	import RawMdiEncryptionExpiration from '~icons/mdi/encryption-expiration';
	import RawMdiAllInclusive from '~icons/mdi/all-inclusive';
	import type { Node } from '$lib/common/types';
	import { getTimeDifference, getTime, getTimeDifferenceColor, toastError, toastSuccess } from '$lib/common/funcs';
	import { disableNodeExpiry, expireNode } from '$lib/common/api';
	import { onMount } from 'svelte';
	import { App } from '$lib/States.svelte';
	import { getToastStore } from '@skeletonlabs/skeleton';

	const ToastStore = getToastStore();

	type NodeExpiresAtProps = {
		node: Node,
		loading?: boolean,
	}

	let { node, loading = $bindable(false) }: NodeExpiresAtProps = $props()

	let diff = $derived.by(() => getTimeDifference(getTime(node.expiry)));

	onMount(() => {
		const interval = setInterval(() => {
			diff = getTimeDifference(getTime(node.expiry));
		}, 1000);

		return () => {
			clearInterval(interval);
		};
	});
</script>

<CardListEntry title="Expires:">
	<div class="flex flex-row items-start text-right justify-end">
		<span class=" {getTimeDifferenceColor(diff)} items-center">
			{diff.message}
		</span>
		{#if diff.finite}
		<span class="items-center" title="Disable key expiry (node never expires)">
			<Delete
				logo={RawMdiAllInclusive}
				func={async () => {
					loading = true
					try {
						App.updateValue(App.nodes, await disableNodeExpiry(node))
						toastSuccess('Disabled expiry for "' + node.givenName + '"', ToastStore)
					} catch (e) {
						if (e instanceof Error) {
							toastError('', ToastStore, e)
						}
					} finally {
						loading = false
					}
				}}
			/>
		</span>
		{/if}
		<span class="items-center" title="Expire node now">
			<Delete
				logo={RawMdiEncryptionExpiration}
				func={async () => {
					loading = true
					try{
						App.updateValue(App.nodes, await expireNode(node))
					} finally {
						loading = false
					}
				}}
			/>
		</span>
	</div>
</CardListEntry>

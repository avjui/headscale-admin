<script lang="ts">
	import { getTime, getTimeDifferenceMessage } from '$lib/common/funcs';
	import type { Node } from '$lib/common/types';
	import { onMount } from 'svelte';
	import CardListEntry from '../CardListEntry.svelte';

	type NodeLastSeenProps = {
		node: Node,
	}
	let { node }: NodeLastSeenProps = $props()

	// ticks every second so the relative time stays current
	let now = $state(Date.now());
	const lastSeen = $derived.by(() => {
		void now; // re-evaluate on every tick
		return getTimeDifferenceMessage(getTime(node.lastSeen));
	});

	onMount(() => {
		const interval = setInterval(() => {
			now = Date.now();
		}, 1000);
		return () => {
			clearInterval(interval);
		};
	});
</script>

<CardListEntry title="Last Seen:">
	{#if node.online}
		Online Now
	{:else}
		{lastSeen}
	{/if}
</CardListEntry>

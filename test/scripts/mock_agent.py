import requests
import httpx
import random
import sys
import string
import logging
import time
import asyncio
from dataclasses import dataclass
from typing import Optional, List

log = logging.getLogger(__name__)

yts_url = "http://localhost:4000"


def random_string(length: int = 100, alphabet=string.ascii_letters):
    return "".join([random.choice(alphabet) for _ in range(length)])


@dataclass
class Context:
    client: httpx.AsyncClient


@dataclass
class Agent:
    ctx: Context
    instance_id: int
    name: str
    seed: int
    is_quest: bool
    self_tick: int = 0

    async def tick(self, current_tick):
        choice = random.randint(1, 100)
        if choice < 3:
            search = await self.search()
            return random.choice(search)
        if self.self_tick % 10 == 0:
            # heartbeat with the server every 10 ticks
            await self.heartbeat()
        self.self_tick += 1

    async def heartbeat(self):
        await self.ctx.client.get(f"{yts_url}/api/v5/hello/stress_test-{self.seed}")

    async def search(self):
        log.info("instance %d: searching...", self.instance_id)
        resp = await self.ctx.client.get(
            f"{yts_url}/api/v5/search?q={random_string()}",
            headers={"user-agent": "UnityWebRequest"},
        )
        if resp.status_code != 200:
            raise AssertionError(f"expected 200, got {resp.status_code}, {resp.text}")
        rjson = resp.json()
        atlas_id = rjson["slot_id"]
        resp = await self.ctx.client.get(f"{yts_url}/a/5/at/{atlas_id}")
        if resp.status_code != 200:
            raise AssertionError(f"expected 200, got {resp.status_code}, {resp.text}")
        return rjson["search_results"]

    async def watch(self, video):
        if self.is_quest:
            user_agent = "stagefright"
        else:
            user_agent = "kldgjaslkj"
        # each agent does /a/5/sl/id for metadata
        resp = await self.ctx.client.get(
            f'{yts_url}/a/5/sl/{video["slot_id"]}',
            headers={"user-agent": user_agent},
        )
        assert resp.status_code == 302
        if not self.is_quest:
            redirect_to = resp.headers["location"]
            if not redirect_to.endswith(video["youtube_id"]):
                raise AssertionError(f'wanted {video["youtube_id"]}, got {redirect_to}')
        resp = await self.ctx.client.get(
            f'{yts_url}/a/5/sl/{video["slot_id"]}',
            headers={"user-agent": "UnityWebRequest"},
        )
        assert resp.status_code == 200


@dataclass
class Instance:
    ctx: Context
    id: int
    seed: int
    agents: list
    video_queue: list
    self_tick: int = 0
    watching_video: Optional[dict] = None

    async def add_agent(self):
        agent = Agent(
            ctx=self.ctx,
            instance_id=self.id,
            name=random_string(),
            # 80 / 20 split between quest and non quest
            is_quest=random.uniform(0, 1) < 0.8,
            seed=self.seed,
        )
        self.agents.append(agent)
        log.info("instance %d, add agent", self.id)
        await agent.heartbeat()
        if self.watching_video:
            await agent.watch(self.watching_video)

    def maybe_remove_agent(self):
        if len(self.agents) == 1:
            return

        index_to_remove = random.choice([idx for idx, _ in enumerate(self.agents)])
        log.info(
            "instance %d, remove agent at index %d (len %d)",
            self.id,
            index_to_remove,
            len(self.agents),
        )
        self.agents.pop(index_to_remove - 1)

    async def tick(self, current_tick):
        random.shuffle(self.agents)

        # every 30 simulated ticks in the instance, one agent refreshes the queue
        if self.self_tick % 30 == 0:
            log.info(
                "instance %d, refreshing queue with %d videos",
                self.id,
                len(self.video_queue),
            )
            for video in self.video_queue:
                resp = await self.ctx.client.get(f"{yts_url}/a/5/qr/{video['slot_id']}")
                assert resp.status_code == 200

        results = []
        if not self.watching_video:
            if not self.video_queue:
                results = await self.agents[0].search()
                await self.watch(random.choice(results), current_tick)
            else:
                # we finished playing a video, and we have queue entry. play it
                new_video_on_queue = self.video_queue.pop(0)
                await self.watch(new_video_on_queue, current_tick)
        else:
            # if we're already watching, go through each agent, see if they want anything
            for agent in self.agents:
                maybe_video = await agent.tick(current_tick)
                # if they do, submit to queue
                if maybe_video:
                    await self.watch(maybe_video, current_tick)

            # tick the duration away
            end_timestamp = self.watching_at + self.watching_video["duration"]
            if current_tick > end_timestamp:
                self.watching_video = None
            else:
                remaining_ticks = end_timestamp - current_tick
                log.info(
                    "instance %d: still watching %s (for %d more ticks)",
                    self.id,
                    self.watching_video["youtube_id"],
                    remaining_ticks,
                )
        self.self_tick += 1

    async def watch(self, video, current_tick):
        if self.watching_video is None:
            log.info("instance %d, watching %r", self.id, video["youtube_id"])
            self.watching_video = video
            self.watching_at = current_tick
            for agent in self.agents:
                await agent.watch(video)
        else:
            if len(self.video_queue) < 30:  # max queue size
                self.video_queue.append(video)
                log.info(
                    "instance %d, add %r to queue (len %d)",
                    self.id,
                    video["youtube_id"],
                    len(self.video_queue),
                )


async def main():
    target_instance_count = int(sys.argv[1])
    target_agents_per_instance = int(sys.argv[2])
    seed = int(time.time())
    logging.basicConfig(level=logging.INFO)
    logging.getLogger("httpx").setLevel(logging.ERROR)
    log.info(
        "seed %d, instance target %d, users per instance %d",
        seed,
        target_instance_count,
        target_agents_per_instance,
    )
    client = httpx.AsyncClient(headers={"Accept": "application/json"})
    ctx = Context(client=client)

    random.seed(seed)
    instances: List[Instance] = []

    current_tick = 0
    while True:
        delta_instance_count = (
            target_instance_count - len(instances)
        ) + random.randint(-5, 5)
        log.info(
            "tick %d with %d instances, (applying delta %d)",
            current_tick,
            len(instances),
            delta_instance_count,
        )
        tasks = []
        if delta_instance_count >= 0:
            tasks.append(asyncio.create_task(create_instance(ctx, instances, seed)))
        else:
            ids_to_remove = []
            for instance in instances:
                if random.randint(0, 100) < 3:
                    ids_to_remove.append(instance.id)

            for id_to_remove in ids_to_remove:
                index_to_remove = None
                for index, instance in enumerate(instances):
                    if instance.id == id_to_remove:
                        index_to_remove = index
                        break

                if index_to_remove is not None:
                    log.info("removing instance %d", instance.id)
                    instances.pop(index_to_remove)

        # for each instance, maybe make players join or leave!
        for instance in instances:
            delta_agent_count = (
                target_agents_per_instance - len(instance.agents)
            ) + random.randint(-5, 5)
            if delta_agent_count >= 0:
                tasks.append(asyncio.create_task(instance.add_agent()))
            else:
                instance.maybe_remove_agent()

        if tasks:
            await asyncio.wait(tasks)

        # simulate the instances
        coros = []
        for instance in instances:
            # not all instances simulate
            if random.randint(0, 100) < 70:
                coros.append(asyncio.create_task(instance.tick(current_tick)))
        if coros:
            await asyncio.wait(coros)
            await asyncio.sleep(0.1)
        current_tick += 1


async def create_instance(ctx, instances, seed):
    instance = Instance(
        ctx=ctx,
        id=random.randint(100, 1000000000),
        seed=seed,
        agents=[],
        video_queue=[],
    )
    log.info("creating instance %d", instance.id)
    await instance.add_agent()  # every instance needs at least one agent (instance master)
    instances.append(instance)


if __name__ == "__main__":
    asyncio.run(main())

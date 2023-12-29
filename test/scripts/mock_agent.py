import requests
import httpx
import random
import sys
import string
import logging
import time
import asyncio
from dataclasses import dataclass
from typing import Optional

log = logging.getLogger(__name__)

yts_url = "http://localhost:4000"


def random_string(length: int = 100, alphabet=string.ascii_letters):
    return "".join([random.choice(alphabet) for _ in range(length)])


@dataclass
class Agent:
    name: str
    is_quest: bool

    async def watch(self, ctx, video):
        if self.is_quest:
            user_agent = "stagefright"
        else:
            user_agent = "kldgjaslkj"
        # each agent does /a/4/sl/id for metadata
        await ctx.client.get(
            f'{yts_url}/a/4/sl/{video["slot_id"]}',
            headers={"user-agent": user_agent},
        )
        await ctx.client.get(
            f'{yts_url}/a/4/sl/{video["slot_id"]}',
            headers={"user-agent": "UnityWebRequest"},
        )


@dataclass
class Context:
    client: httpx.AsyncClient


@dataclass
class Instance:
    id: int
    seed: int
    agents: list
    video_queue: list
    watching_video: Optional[dict] = None

    def add_agent(self):
        self.agents.append(
            Agent(name=random_string(), is_quest=random.choice([False, True]))
        )
        requests.get(f"{yts_url}/api/v4/hello/stress_test-{self.seed}")

    async def tick(self, ctx, current_tick):
        results = []

        random.shuffle(self.agents)

        results = []
        if not self.watching_video:
            log.info("instance %d: searching and watching", self.id)
            for agent in self.agents[:5]:
                resp = await ctx.client.get(
                    f"{yts_url}/api/v4/search?q={random_string()}",
                    headers={"user-agent": "UnityWebRequest"},
                )
                if resp.status_code != 200:
                    raise AssertionError(
                        f"expected 200, got {resp.status_code}, {resp.text}"
                    )
                results.append(resp.json())

            search = random.choice(results)

            await self.watch(ctx, random.choice(search["search_results"]), current_tick)
        else:
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

    async def watch(self, ctx, video, current_tick):
        self.watching_video = video
        self.watching_at = current_tick
        for agent in self.agents:
            await agent.watch(ctx, video)


async def main():
    instance_count = int(sys.argv[1])
    agents_per_instance = int(sys.argv[2])
    seed = int(time.time())
    logging.basicConfig(level=logging.INFO)
    log.info("seed %d", seed)
    client = httpx.AsyncClient(headers={"Accept": "application/json"})
    ctx = Context(client=client)

    random.seed(seed)
    instances = [
        Instance(
            id=x,
            seed=seed,
            agents=[],
            video_queue=[],
        )
        for x in range(instance_count)
    ]

    for instance in instances:
        for _ in range(agents_per_instance):
            instance.add_agent()

    current_tick = 0
    while True:
        log.info("tick %d...", current_tick)
        coros = []
        for instance in instances:
            coros.append(asyncio.create_task(instance.tick(ctx, current_tick)))
        await asyncio.wait(coros)
        await asyncio.sleep(0.1)
        current_tick += 1


if __name__ == "__main__":
    asyncio.run(main())

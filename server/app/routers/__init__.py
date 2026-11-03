from fastapi import BackgroundTasks, Request

from ..services import push


def schedule_push(
    request: Request, background: BackgroundTasks, notification_ids: list[int]
) -> None:
    """Sends the pushes after the response, so the caller never waits for FCM."""
    if notification_ids:
        state = request.app.state
        background.add_task(
            push.deliver, state.pool, state.push_sender, notification_ids, state.settings
        )

import os
import json
import time
import pytest
import pika

from unittest.mock import MagicMock, patch
from rabbitmq.setup import setup_rabbitmq_topology, get_connection, EXCHANGE_NAME, QUEUES, BINDINGS


def test_setup_rabbitmq_topology_mocked():
    """Unit test using mock pika blocking connection to test topology calls."""
    mock_conn = MagicMock()
    mock_channel = MagicMock()
    mock_conn.channel.return_value = mock_channel

    with patch("rabbitmq.setup.get_connection", return_value=mock_conn):
        setup_rabbitmq_topology(retries=1, delay=0)

    # Assert Exchange declaration
    mock_channel.exchange_declare.assert_called_once_with(
        exchange="edura.events", exchange_type="topic", durable=True, passive=False
    )

    # Assert Queue declarations
    assert mock_channel.queue_declare.call_count == len(QUEUES)
    for q in QUEUES:
        mock_channel.queue_declare.assert_any_call(queue=q, durable=True, passive=False)

    # Assert Bindings declarations
    assert mock_channel.queue_bind.call_count == len(BINDINGS)
    for q, rk in BINDINGS:
        mock_channel.queue_bind.assert_any_call(queue=q, exchange="edura.events", routing_key=rk)


@pytest.fixture(scope="module")
def rabbitmq_conn():
    # Setup topology before running tests
    os.environ["RABBITMQ_HOST"] = os.getenv("RABBITMQ_HOST", "localhost")
    os.environ["RABBITMQ_PORT"] = os.getenv("RABBITMQ_PORT", "5672")
    os.environ["RABBITMQ_USER"] = os.getenv("RABBITMQ_USER", "guest")
    os.environ["RABBITMQ_PASSWORD"] = os.getenv("RABBITMQ_PASSWORD", "guest")

    try:
        connection = get_connection()
        yield connection
        if not connection.is_closed:
            connection.close()
    except pika.exceptions.AMQPConnectionError:
        pytest.skip("RabbitMQ instance is not available for integration testing.")


def test_setup_idempotency(rabbitmq_conn):
    """Test that running setup multiple times is idempotent and produces no errors."""
    setup_rabbitmq_topology(retries=3, delay=1)
    setup_rabbitmq_topology(retries=3, delay=1)


def test_topology_queues_and_exchange_declared(rabbitmq_conn):
    """Verify exchange and queues are passive-declared without error."""
    channel = rabbitmq_conn.channel()

    # Passive declare check for exchange
    channel.exchange_declare(exchange=EXCHANGE_NAME, exchange_type="topic", passive=True)

    # Passive declare check for queues
    for q in QUEUES:
        declare_ok = channel.queue_declare(queue=q, passive=True)
        assert declare_ok.method.queue == q


def test_pub_sub_smoke(rabbitmq_conn):
    """Publish payment.success event and verify it reaches both enrollment.queue and notification.queue."""
    channel = rabbitmq_conn.channel()

    # Purge queues before test
    channel.queue_purge(queue="enrollment.queue")
    channel.queue_purge(queue="notification.queue")

    test_payload = {
        "event": "payment.success",
        "student_id": 1,
        "course_id": 101,
        "amount": 49.99
    }

    # Publish message
    channel.basic_publish(
        exchange=EXCHANGE_NAME,
        routing_key="payment.success",
        body=json.dumps(test_payload),
        properties=pika.BasicProperties(
            delivery_mode=2,
            content_type="application/json"
        )
    )

    # Allow broker processing time
    time.sleep(0.5)

    # Consume from enrollment.queue
    method_frame, header_frame, body = channel.basic_get(queue="enrollment.queue", auto_ack=True)
    assert method_frame is not None, "Message not received in enrollment.queue"
    received_msg = json.loads(body.decode("utf-8"))
    assert received_msg["event"] == "payment.success"
    assert received_msg["student_id"] == 1

    # Consume from notification.queue
    method_frame_n, header_frame_n, body_n = channel.basic_get(queue="notification.queue", auto_ack=True)
    assert method_frame_n is not None, "Message not received in notification.queue"
    received_msg_n = json.loads(body_n.decode("utf-8"))
    assert received_msg_n["event"] == "payment.success"

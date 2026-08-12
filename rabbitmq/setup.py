import os
import sys
import time
import logging
import pika

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

EXCHANGE_NAME = "edura.events"
EXCHANGE_TYPE = "topic"

QUEUES = [
    "notification.queue",
    "enrollment.queue",
    "progress.queue",
]

BINDINGS = [
    ("notification.queue", "auth.otp-requested"),
    ("enrollment.queue", "payment.success"),
    ("notification.queue", "payment.success"),
    ("notification.queue", "payment.manual-uploaded"),
    ("progress.queue", "enrollment.activated"),
    ("progress.queue", "assessment.graded"),
    ("notification.queue", "assessment.graded"),
    ("notification.queue", "certificate.issued"),
    ("progress.queue", "lesson.watched"),
]


def get_connection():
    rabbitmq_url = os.getenv("RABBITMQ_URL")
    if rabbitmq_url:
        params = pika.URLParameters(rabbitmq_url)
    else:
        host = os.getenv("RABBITMQ_HOST", "rabbitmq")
        port = int(os.getenv("RABBITMQ_PORT", "5672"))
        user = os.getenv("RABBITMQ_USER", "guest")
        password = os.getenv("RABBITMQ_PASSWORD", "guest")
        credentials = pika.PlainCredentials(user, password)
        params = pika.ConnectionParameters(host=host, port=port, credentials=credentials)
    
    return pika.BlockingConnection(params)


def setup_rabbitmq_topology(retries=10, delay=3):
    connection = None
    for attempt in range(1, retries + 1):
        try:
            logger.info("Connecting to RabbitMQ (attempt %d/%d)...", attempt, retries)
            connection = get_connection()
            logger.info("Connected to RabbitMQ successfully.")
            break
        except pika.exceptions.AMQPConnectionError as err:
            logger.warning("RabbitMQ connection failed: %s. Retrying in %d seconds...", err, delay)
            if attempt == retries:
                logger.error("Could not connect to RabbitMQ after %d attempts.", retries)
                raise
            time.sleep(delay)

    try:
        channel = connection.channel()

        # Declare Exchange
        logger.info("Declaring topic exchange: '%s'...", EXCHANGE_NAME)
        channel.exchange_declare(
            exchange=EXCHANGE_NAME,
            exchange_type=EXCHANGE_TYPE,
            durable=True,
            passive=False,
        )

        # Declare Queues
        for queue_name in QUEUES:
            logger.info("Declaring queue: '%s'...", queue_name)
            channel.queue_declare(
                queue=queue_name,
                durable=True,
                passive=False,
            )

        # Bind Queues to Exchange with Routing Keys
        for queue_name, routing_key in BINDINGS:
            logger.info("Binding queue '%s' to exchange '%s' with routing key '%s'...", queue_name, EXCHANGE_NAME, routing_key)
            channel.queue_bind(
                queue=queue_name,
                exchange=EXCHANGE_NAME,
                routing_key=routing_key,
            )

        logger.info("RabbitMQ topology setup completed successfully.")
    finally:
        if connection and not connection.is_closed:
            connection.close()


if __name__ == "__main__":
    try:
        setup_rabbitmq_topology()
    except Exception as e:
        logger.error("Failed to set up RabbitMQ topology: %s", e)
        sys.exit(1)

import logging
import os
import sys
import time

import pika

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

EXCHANGE_NAME = "edura.events"
EXCHANGE_TYPE = "topic"

# ---------------------------------------------------------------------------
# Broker topology. Services never call each other over HTTP: every change is an
# event on the ``edura.events`` topic exchange, and each consuming service reads
# its own durable queue. Routing keys are listed once, below, per queue.
# ---------------------------------------------------------------------------
QUEUES = [
    "user.queue",
    "course.queue",
    "content.queue",
    "enrollment.queue",
    "payment.queue",
    "assessment.queue",
    "progress.queue",
    "notification.queue",
    "admin.queue",
    "analytics.queue",
]

# Queues from earlier versions that nothing reads any more; setup removes them.
OBSOLETE_QUEUES = ["user.referrals.queue"]

# queue -> routing keys. Mirrors edura-backend/shared/events.py (QUEUES), the single
# source of truth the services bind their consumers from.
BINDINGS = [
    ("user.queue", "auth.user-registered"),
    ("user.queue", "auth.account-updated"),
    ("user.queue", "enrollment.activated"),
    ("course.queue", "access.changed"),
    ("content.queue", "access.changed"),
    ("enrollment.queue", "payment.success"),
    ("enrollment.queue", "subscription.expired"),
    ("enrollment.queue", "course.upserted"),
    ("enrollment.queue", "course.deleted"),
    ("enrollment.queue", "user.profile-upserted"),
    ("enrollment.queue", "user.profile-deleted"),
    ("enrollment.queue", "user.stream-upserted"),
    ("enrollment.queue", "user.stream-deleted"),
    ("payment.queue", "course.upserted"),
    ("payment.queue", "course.deleted"),
    ("assessment.queue", "access.changed"),
    ("assessment.queue", "course.upserted"),
    ("assessment.queue", "course.deleted"),
    ("assessment.queue", "user.profile-upserted"),
    ("assessment.queue", "user.profile-deleted"),
    ("assessment.queue", "auth.user-registered"),
    ("assessment.queue", "auth.account-updated"),
    ("progress.queue", "enrollment.activated"),
    ("progress.queue", "assessment.graded"),
    ("progress.queue", "lesson.watched"),
    ("notification.queue", "auth.otp-requested"),
    ("notification.queue", "auth.email-verification-requested"),
    ("notification.queue", "auth.password-reset-requested"),
    ("notification.queue", "auth.password-changed"),
    ("notification.queue", "payment.success"),
    ("notification.queue", "payment.manual-uploaded"),
    ("notification.queue", "assessment.graded"),
    ("notification.queue", "certificate.issued"),
    ("notification.queue", "proctoring.violation"),
    ("notification.queue", "violation.alert"),
    ("notification.queue", "report.progress"),
    ("admin.queue", "user.profile-upserted"),
    ("admin.queue", "user.profile-deleted"),
    ("admin.queue", "auth.user-registered"),
    ("admin.queue", "auth.account-updated"),
    ("analytics.queue", "auth.user-registered"),
    ("analytics.queue", "auth.account-updated"),
    ("analytics.queue", "user.profile-upserted"),
    ("analytics.queue", "user.profile-deleted"),
    ("analytics.queue", "course.upserted"),
    ("analytics.queue", "course.deleted"),
    ("analytics.queue", "course.module-upserted"),
    ("analytics.queue", "course.module-deleted"),
    ("analytics.queue", "access.changed"),
    ("analytics.queue", "enrollment.changed"),
    ("analytics.queue", "payment.success"),
    ("analytics.queue", "payment.receipt-uploaded"),
    ("analytics.queue", "payment.receipt-reviewed"),
    ("analytics.queue", "assessment.upserted"),
    ("analytics.queue", "assessment.deleted"),
    ("analytics.queue", "assessment.graded"),
    ("analytics.queue", "badge.awarded"),
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
        params = pika.ConnectionParameters(
            host=host, port=port, credentials=credentials
        )

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
            logger.warning(
                "RabbitMQ connection failed: %s. Retrying in %d seconds...", err, delay
            )
            if attempt == retries:
                logger.error(
                    "Could not connect to RabbitMQ after %d attempts.", retries
                )
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

        # Remove queues nothing reads any more, so they stop collecting messages.
        for queue_name in OBSOLETE_QUEUES:
            logger.info("Removing obsolete queue: '%s'...", queue_name)
            channel.queue_delete(queue=queue_name)

        # Bind Queues to Exchange with Routing Keys
        for queue_name, routing_key in BINDINGS:
            logger.info(
                "Binding queue '%s' to exchange '%s' with routing key '%s'...",
                queue_name,
                EXCHANGE_NAME,
                routing_key,
            )
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

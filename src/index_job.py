"""Cloud Run Job entry point for indexing research papers."""

import logging

from src.rag import index_papers

logger = logging.getLogger(__name__)


def main() -> None:
    """Run the indexing pipeline once and log the result."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    result = index_papers()
    logger.info(
        "Indexed %s chunks from %s pages into namespace %s.",
        result.indexed_chunks,
        result.loaded_pages,
        result.namespace,
    )


if __name__ == "__main__":
    main()

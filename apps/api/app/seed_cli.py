from app.core.database import SessionLocal, create_schema
from app.seed import seed_database


def main() -> None:
    create_schema()
    with SessionLocal() as db:
        seed_database(db)
    print("Fan OS development seed is ready.")


if __name__ == "__main__":
    main()

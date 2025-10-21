
.PHONY: dev seed
dev:
	python -m flask --app app.main run --port 5001 --debug
seed:
	psql $$DATABASE_URL -f supabase/migrations/02_seed.sql

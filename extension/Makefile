EXTENSION = factstr
DATA = sql/factstr--0.1.0.sql
REGRESS = append query append_if

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

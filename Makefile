.PHONY: all install installcheck clean

all:
	$(MAKE) -C extension all

install:
	$(MAKE) -C extension install

installcheck:
	$(MAKE) -C extension installcheck

clean:
	$(MAKE) -C extension clean

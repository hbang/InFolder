all:
ifeq ($(shell uname -n),kirbmini.local)
	tar cf /tmp/infolder.tar InFolder.app Makefile
	scp /tmp/infolder.tar kirb@kirbtest.local:/tmp/
	ssh kirb@kirbtest.local "rm -rf /tmp/InFolder.app /tmp/InFolder*.dmg; cd /tmp; tar xf /tmp/infolder.tar; make"
	scp kirb@kirbtest.local:/tmp/InFolder*.dmg .
else
	@which dropdmg > /dev/null || (echo "DropDMG and its command line tool are required" 2>&1; exit 1)
	dropdmg --config-name=infolder InFolder.app
endif

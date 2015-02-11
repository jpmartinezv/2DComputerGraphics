# mac os x with macports
PKG:=PKG_CONFIG_PATH=macosx/lib/pkgconfig pkg-config
CXXFLAGS:=-std=c++11 -O2 -W -Wall -fvisibility=hidden
LDFLAGS:=-bundle -undefined dynamic_lookup
LUAINC:=$(shell pkg-config --cflags --static lua)

# ubuntu
#PKG:=PKG_CONFIG_PATH=linux/lib/pkgconfig pkg-config
#LUAINC:=$(shell pkg-config --cflags --static lua5.2)
#CXXFLAGS:=-fPIC -std=c++11 -O2 -W -Wall -fvisibility=hidden
#LDFLAGS:=-shared -fPIC

# common to both
FTINC:=$(shell $(PKG) --cflags --static freetype2)
FTLIB:=$(shell $(PKG) --libs --static freetype2)
PNGINC:=$(shell $(PKG) --cflags --static libpng)
PNGLIB:=$(shell $(PKG) --libs --static libpng)
BASE64LIB=$(shell $(PKG) --libs --static b64)
BASE64INC=$(shell $(PKG) --cflags --static b64)
IMAGEOBJ:=luaimage.o pngio.o image.o
BASE64OBJ:=luabase64.o
FTOBJ:=luafreetype.o
CHRONOSOBJ:=luachronos.o chronos.o

%.o: %.cpp
	@echo compiling $<
	@$(CXX) $(CXXFLAGS) $(INC) -o $@ -c $<

$(IMAGEOBJ): INC := $(LUAINC) $(PNGINC)
$(BASE64OBJ): INC := $(LUAINC) $(BASE64INC)
$(FTOBJ): INC := $(LUAINC) $(FTINC)
$(CHRONOSOBJ): INC := $(LUAINC)

all: image.so base64.so freetype.so chronos.so

luafreetype.o: luafreetype.cpp luafreetype.h
image.o: image.cpp image.h
luabase64.o: luabase64.cpp luabase64.h
luaimage.o: luaimage.cpp luaimage.h image.h pngio.h
pngio.o: pngio.cpp image.h pngio.h
chronos.o: chronos.cpp chronos.h
luachronos.o: luachronos.cpp luachronos.h

chronos.so: $(CHRONOSOBJ)
	@echo linking $@
	@$(CXX) $(LDFLAGS) -o $@ $(CHRONOSOBJ)

image.so: $(IMAGEOBJ)
	@echo linking $@
	@$(CXX) $(LDFLAGS) -o $@ $(IMAGEOBJ) $(PNGLIB)

base64.so: $(BASE64OBJ)
	@echo linking $@
	@$(CXX) $(LDFLAGS) -o $@ $(BASE64OBJ) $(BASE64LIB)

freetype.so: $(FTOBJ)
	@echo linking $@
	@$(CXX) $(LDFLAGS) -o $@ $(FTOBJ) $(FTLIB)

clean:
	\rm -f $(IMAGEOBJ) $(BASE64OBJ) $(FTOBJ) $(CHRONOSOBJ)

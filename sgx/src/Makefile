
SGX_SDK ?= /opt/intel/sgxsdk
SGX_LIBRARY_PATH := $(SGX_SDK)/lib64
Include_Paths = -I$(SGX_SDK)/include -Iinclude -Iutils -Ilog -I/opt/crust/tools/openssl/include

Urts_Library_Name := sgx_urts

C_Link_Flags = $(Include_Paths) -L$(SGX_LIBRARY_PATH) -lpthread -ldl -L/opt/crust/tools/openssl/lib -lssl -lcrypto -Wl,-R/opt/crust/tools/openssl/lib -l:libsgx_tservice.a -lsgx_launch -lsgx_dcap_ql -lsgx_dcap_quoteverify -lsgx_urts -l:libsgx_tcrypto.a
Cpp_Link_Flags := -std=c++11 $(C_Link_Flags)

Cpp_Files := $(wildcard *.cpp) $(wildcard utils/*.cpp) $(wildcard log/*.cpp)
Cpp_Objects := $(Cpp_Files:.cpp=.o)
C_Files := $(wildcard utils/*.c)
C_Objects := $(C_Files:.c=.o)

App_Name := dcap-service


all: $(App_Name)

utils/%.o : utils/%.c
	@$(CC) $(C_Link_Flags) -c $< -o $@
	@echo "CC   <=  $<"

%.o : %.cpp
	@$(CXX) $(Cpp_Link_Flags) -c $< -o $@
	@echo "CXX  <=  $<"

$(App_Name) : $(Cpp_Objects) $(C_Objects)
	@$(CXX) -o $@ $^ $(C_Link_Flags) $(Cpp_Link_Flags)
	@echo "LINK =>  $@"


clean:
	@rm -f $(App_Name) $(Cpp_Objects) $(C_Objects)

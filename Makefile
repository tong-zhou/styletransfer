PROJECT := caffe
NAME := lib$(PROJECT).so
LIB := lib$(PROJECT).a
TEST_NAME := test_$(PROJECT)
layer_folders := src/caffe/layers/activation  src/caffe/layers/operator src/caffe/layers/loss src/caffe/layers/func src/caffe/layers/data
CXX_SRCS := $(shell find src/caffe $(layer_folders) src/caffe/util src/caffe/solvers -maxdepth 1 -name "*.cpp")
CU_SRCS := $(shell find $(layer_folders) src/caffe/util src/caffe -maxdepth 1 -name "*.cu")
TEST_SRCS := $(shell find src/caffe/test -maxdepth 1 -name "test_*.cpp")
GTEST_SRCS := src/gtest/gtest-all.cpp src/gtest/test_caffe_main.cpp
TOOL_SRCS := $(shell find tools -maxdepth 1 -name "*.cpp")
PROTO_SRCS := $(wildcard src/caffe/proto/*.proto)
PROTO_GEN_HEADER := ${PROTO_SRCS:.proto=.pb.h}
PROTO_GEN_CC := ${PROTO_SRCS:.proto=.pb.cc}

CXX_OBJS_ := ${CXX_SRCS:.cpp=.o}
CU_OBJS_ := ${CU_SRCS:.cu=.o}
PROTO_OBJS_ := ${PROTO_SRCS:.proto=.pb.o}

CXX_OBJS = $(foreach file,$(CXX_OBJS_),build/$(file))
CU_OBJS = $(foreach file,$(CU_OBJS_),build/cuda/$(file))
PROTO_OBJS = $(foreach file,$(PROTO_OBJS_),build/$(file))

OBJS := $(CXX_OBJS) $(CU_OBJS) $(PROTO_OBJS)


TOOL_OBJS_ := ${TOOL_SRCS:.cpp=.o}
TOOL_OBJS = $(foreach file,$(TOOL_OBJS_),build/$(file))


GTEST_OBJS_ := ${GTEST_SRCS:.cpp=.o}
GTEST_OBJS = $(foreach file,$(GTEST_OBJS_),build/$(file))

TEST_OBJS_ := ${TEST_SRCS:.cpp=.o}
TEST_OBJS = $(foreach file,$(TEST_OBJS_),build/$(file))

TEST_BINS := ${TEST_OBJS:.o=.testbin}
TOOL_BINS :=${TOOL_OBJS:.o=.bin}

CUDA_DIR := /usr/local/cuda
CUDA_ARCH :=-gencode arch=compute_35,code=sm_35 \
		-gencode arch=compute_50,code=sm_50 \
		-gencode arch=compute_50,code=compute_50


CUDA_INCLUDE_DIR := $(CUDA_DIR)/include
CUDA_LIB_DIR := $(CUDA_DIR)/lib64

INCLUDE_DIRS := /home/shen/caffe/thirdparty/cudnn/include . src /usr/local/include $(CUDA_INCLUDE_DIR)  include /home/shen/caffe/thirdparty/nccl/include /home/shen/caffe/thirdparty/blas/include /home/shen/caffe/thirdparty/mpich/include
LIBRARY_DIRS := /home/shen/caffe/thirdparty/cudnn/lib64 . /usr/lib /usr/local/lib $(CUDA_LIB_DIR) /home/shen/caffe/thirdparty/nccl/lib /home/shen/caffe/thirdparty/blas/lib /home/shen/caffe/thirdparty/mpich/lib
LIBRARIES := glog gflags protobuf boost_system boost_filesystem boost_regex m  opencv_core opencv_highgui opencv_imgproc boost_thread stdc++  cudnn openblas
LIBRARIES += cudart cublas curand nccl mpi
WARNINGS := -Wall

CXXFLAGS +=  -MMD -MP -fPIC -fopenmp
LDFLAGS += $(foreach librarydir,$(LIBRARY_DIRS),-L$(librarydir))
LDFLAGS += $(foreach library,$(LIBRARIES),-l$(library))
LDFLAGS +=  -lgomp

LINK = $(CXX) $(CXXFLAGS) $(CPPFLAGS) $(LDFLAGS) $(WARNINGS)
NVCC = nvcc $(CPPFLAGS) $(CUDA_ARCH)

COMMON_FLAGS := $(foreach includedir,$(INCLUDE_DIRS),-I$(includedir))  -DUSE_CUDNN
NVCCFLAGS := -ccbin=$(CXX) -Xcompiler -fPIC -Xcompiler  -fopenmp
DEBUG := 0
# Debugging
ifeq ($(DEBUG), 1)
	COMMON_FLAGS += -DDEBUG -g -O0 
	NVCCFLAGS += -G
else
	COMMON_FLAGS += -DNDEBUG -O3
endif

NVCCFLAGS += $(COMMON_FLAGS)


#---------------------------------------------------------------------------------------------------------

DEPS := ${CXX_OBJS:.o=.d} ${CU_OBJS:.o=.d} ${TEST_OBJS:.o=.d} ${GTEST_OBJS:.o=.d} ${TOOL_OBJS:.o=.d}

.PHONY: all test clean

all: $(NAME) $(TOOL_BINS) $(LIB)

-include $(DEPS)

test: $(TEST_BINS) $(GTEST_OBJS) $(GTEST_MAIN) $(OBJS)
#---------------------------------------------- matlab ------------------------------------------------
matcaffe: all
	/usr/local/MATLAB/R2014b/bin/mex matlab/matcaffe.cpp \
															     CXX="g++" \
															     CXXFLAGS="\$$CXXFLAGS $(CXXFLAGS) $(COMMON_FLAGS) -Wno-uninitialized" \
																	 CXXLIBS="\$$LIBRARIES 	-Wl,--whole-archive lib$(PROJECT).a -Wl,--no-whole-archive  $(LDFLAGS)" \
																	 -output matlab/caffe

#---------------------------------------------  python -------------------------------------------------
pycaffe: all
	$(CXX) -I/home/shen/.local/lib/python2.7/site-packages/numpy/core/include/ $(CXXFLAGS)  $(COMMON_FLAGS) -shared  python/_pycaffe.cpp -lboost_python \
	-I/usr/include/python2.7/  -Wl,--whole-archive lib$(PROJECT).a -Wl,--no-whole-archive  \
	$(LDFLAGS) -fPIC  -o python/_pycaffe.so 
#---------------------------------------------- link ---------------------------------------------------
$(TEST_BINS): %.testbin : %.o $(OBJS) $(GTEST_OBJS) $(GTEST_MAIN)
	@ echo LD -o $<
	@ $(CXX)  $< $(GTEST_OBJS) $(GTEST_MAIN)  $(OBJS)  -o $@ $(LDFLAGS) $(COMMON_FLAGS) $(WARNINGS)

$(TOOL_BINS): %.bin : %.o $(OBJS)
	@ echo LD -o $<
	@ $(CXX)  $< $(OBJS) -o $@ $(COMMON_FLAGS) $(LDFLAGS) $(WARNINGS)

$(NAME): $(OBJS)
	@ echo LD -o $@
	@$(LINK) -shared $(OBJS) -o $(NAME) $(COMMON_FLAGS)

$(LIB):  $(OBJS)
	@ echo AR -o $@
	@ ar rcs $@ $(OBJS)
#---------------------------------------------- compile -------------------------------------------------
$(TEST_OBJS): build/%.o: %.cpp
	@ echo CXX $<
	@$(CXX) $(CXXFLAGS) $(COMMON_FLAGS) -c $< -o $@ 

$(GTEST_OBJS): build/%.o: %.cpp
	@ echo CXX $<
	@$(CXX) $(CXXFLAGS) $(COMMON_FLAGS) -c $< -o $@ 

$(TOOL_OBJS): build/%.o: %.cpp 
	@ echo CXX $<
	@$(CXX) $(CXXFLAGS) $(COMMON_FLAGS) -c $< -o $@ 

$(CU_OBJS): build/cuda/%.o: %.cu $(PROTO_GEN_CC)
	@ echo NVCC $< 
	@$(NVCC) $(NVCCFLAGS) -M $< -o ${@:.o=.d} -odir $(@D)
	@$(NVCC) $(NVCCFLAGS) -c $< -o $@ 

$(CXX_OBJS): build/%.o: %.cpp $(PROTO_GEN_CC)
	@ echo CXX $<
	@$(CXX) $(CXXFLAGS) $(COMMON_FLAGS) -c $< -o $@ 

$(PROTO_OBJS): $(PROTO_GEN_CC)
	@ echo CXX $<
	@$(CXX) $(CXXFLAGS) $(COMMON_FLAGS) -c $< -o $@
	 
$(PROTO_GEN_CC): $(PROTO_SRCS)
	@ mkdir -p $(foreach file,$(layer_folders),build/$(file)) build/src/caffe/solvers build/src/caffe/proto build/src/caffe/test build/src/gtest  build/src/caffe/util  build/tools 
	@ mkdir -p $(foreach file,$(layer_folders),build/cuda/$(file)) build/cuda/src/caffe/proto build/cuda/src/caffe/test build/cuda/src/gtest build/cuda/src/caffe  build/cuda/src/caffe/util  build/cuda/tools
	@ echo PROTOC -o $@
	@ protoc $(PROTO_SRCS) --cpp_out=.

clean:
	@- $(RM) -rf build
	@- $(RM) $(PROTO_GEN_HEADER) $(PROTO_GEN_CC)
	@- $(RM) libcaffe.a libcaffe.so

#include "vrconverter.h"
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <stdio.h>

__global__ void makeMap(uint* maps, int rows, int cols, int eyeWidth);
__global__ void notPersistentMapping(uchar* inputImage, uint* gpuMap, uchar* outputImage, int rows, int cols, int eyeWidth);

extern "C" __declspec(dllexport) void test(char* filepath, char* properties) {
    cv::VideoCapture video;
    video.open(filepath);
    if (!video.isOpened()) {
        return;
    }
    int height = video.get(cv::CAP_PROP_FRAME_HEIGHT);
    int width = video.get(cv::CAP_PROP_FRAME_WIDTH);

    string outputProperties = to_string(width) + "X" + to_string(height);
    strcpy(properties, outputProperties.c_str());
}


extern "C" __declspec(dllexport) void runAVI(char* filepath) {
    cv::VideoCapture video;
    video.open(filepath);
    if (!video.isOpened()) {
        return;
    }

    cv::Mat image;
	cv::Mat outimage;
	int height = video.get(cv::CAP_PROP_FRAME_HEIGHT);
	int width = video.get(cv::CAP_PROP_FRAME_WIDTH);
	uint* maps;
	cudaMalloc(&maps, sizeof(uint) * height * width);
	cudaMemset(maps, 0, sizeof(uint) * height * width);

	dim3 blocks(32, 32);
	dim3 grid(ceil((float)width / blocks.x), ceil((float)height / blocks.y));

	makeMap << <grid, blocks>> > (maps, height, width, 80);
	cudaDeviceSynchronize();

	uchar* gpuInput, *gpuOutput;
	cudaMalloc(&gpuInput, sizeof(uchar) * height * width * 3);
	cudaMalloc(&gpuOutput, sizeof(uchar) * height * width * 3);

	image = cv::Mat(height, width, CV_8UC3);
	outimage = cv::Mat(height, width, CV_8UC3);
	cudaMallocHost(&image.data, sizeof(uchar) * height * width * 3);
	cudaMallocHost(&outimage.data, sizeof(uchar) * height * width * 3);

    while (cv::waitKey(1) != 27) {
        video >> image;
        if (image.empty()) {
            cv::destroyWindow("images");
            break;
        }
		cudaMemcpy(gpuInput, image.data, sizeof(uchar)*height*width*3, cudaMemcpyHostToDevice);
		notPersistentMapping << <grid, blocks >> > (gpuInput, maps, gpuOutput, height, width, 80);
		cudaDeviceSynchronize();
		cudaMemcpy(outimage.data, gpuOutput, sizeof(uchar) * height * width * 3, cudaMemcpyDeviceToHost);
        cv::imshow("images", outimage);
    }
}

__global__ void makeMap(uint* maps, int rows, int cols, int eyeWidth) {

	double cx = (double)cols / 2; //width half is center of x
	double cy = (double)rows / 2; //height half is center of y
	double k1 = 0.0, k2 = 0.0;
	if (rows == 2160) {
		k1 = 0.000000014; k2 = 0.000000000000015;
	}
	else if (rows == 1080) {
		k1 = 0.000000037; k2 = 0.00000000000015;
	}
	else if (rows == 4320) {
		k1 = 0.000000007; k2 = 0.0000000000000007;
	}
	//k2 Ä¿Áú¼ö·Ï µÕ±×·¡Áü, k1 Ä¿Áú¼ö·Ï ¹º°¡ ³³ÀÛÇØº¸¿©Áü

	//set index
	int idxX = blockDim.x * blockIdx.x + threadIdx.x;
	int idxY = blockDim.y * blockIdx.y + threadIdx.y;

	if (idxX > cols || idxY > rows) return;

	double rsqaure = pow(cx - idxX, 2) + pow(cy - idxY, 2);
	double hypo = 1 + rsqaure * k1 + pow(rsqaure, 2) * k2; // 1+ kr^2 + kr^4

	int Xd = (idxX - cx) / hypo + cx;
	int Yd = (idxY - cy) / hypo + cy;


	double dCol = (double)cols / (cols/2); // target img 2560*1440, so streoscopic image has 1280*1440
	double dRow = (double)rows / rows; //

	//left img 0 to cols-eyeWidth, right img eyeWidth to cols
	if (Xd < 0 || Yd < 0 || Xd >= cols || Yd >= rows || (idxX % (int)dCol != 0) || (idxY % (int)dRow != 0)) return;
	//idxX % (int)dCol != 0 || idxY % (int)dRow != 0 --> image resize(reduction)

	if (idxX < cols - eyeWidth) {
		//maps[(int)(ny / dRow) * (int)TARGET_WIDTH + (int)(nx / dCol)] = (cols > rows) ? idxX * cols + idxY : idxY * (rows + 1) + idxX;
		maps[(int)(Yd / dRow) * (int)cols + (int)(Xd / dCol)] = (cols > rows) ? idxX * cols + idxY : idxY * (rows + 1) + idxX;
	}
	if (idxX > eyeWidth) {
		//maps[(int)(ny / dRow) * (int)TARGET_WIDTH + (int)(nx / dCol) + (int)TARGET_WIDTH_HALF] = (cols > rows) ? idxX * cols + idxY : idxY * (rows + 1) + idxX;
		maps[(int)(Yd / dRow) * (int)cols + (int)(Xd / dCol) + (int)cols/2] = (cols > rows) ? idxX * cols + idxY : idxY * (rows + 1) + idxX;
	}


	__syncthreads();
}

__global__ void notPersistentMapping(uchar* inputImage, uint* gpuMap, uchar* outputImage, int rows, int cols, int eyeWidth) {
	int idxX = blockDim.x * blockIdx.x + threadIdx.x;
	int idxY = blockDim.y * blockIdx.y + threadIdx.y;

	if (idxX >= cols || idxY >= rows) return;

	int param = (cols > rows) ? cols : rows + 1;

	int dx = 0; int dy = 0;
	dx = gpuMap[idxY * (int)(cols)+idxX] / param;
	dy = gpuMap[idxY * (int)(cols)+idxX] % param;


	if (dy * cols * 3 + dx * 3 >= rows * cols * 3)return;

	if (gpuMap[idxY * (int)(cols)+idxX] != 0) {
		outputImage[idxY * (int)(cols) * 3 + idxX * 3 + 0] = inputImage[dy * (int)(cols) * 3 + dx * 3 + 0];
		outputImage[idxY * (int)(cols) * 3 + idxX * 3 + 1] = inputImage[dy * (int)(cols) * 3 + dx * 3 + 1];
		outputImage[idxY * (int)(cols) * 3 + idxX * 3 + 2] = inputImage[dy * (int)(cols) * 3 + dx * 3 + 2];
	}

	__syncthreads();
}
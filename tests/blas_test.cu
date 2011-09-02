#include <stdio.h>
#include <stdlib.h>

#include <quda_internal.h>
#include <color_spinor_field.h>
#include <blas_quda.h>

#include <test_util.h>


// volume per GPU (full lattice dimensions)
const int LX = 16;
const int LY = 16;
const int LZ = 16;
const int LT = 16;
const int Nspin = 4;

// corresponds to 10 iterations for V=24^4, Nspin = 4, at half precision
const int Niter = 10 * (24*24*24*24*4) / (LX * LY * LZ * LT * Nspin);
//const int Niter = 1;


const int Nkernels = 33;
const int ThreadMin = 32;
const int ThreadMax = 1024;
const int GridMin = 1;
const int GridMax = 1024;//65536; // can remove this with the appropriate data output order for the first reduction output

cpuColorSpinorField *xH, *yH, *zH, *wH, *vH, *hH, *lH;
cudaColorSpinorField *xD, *yD, *zD, *wD, *vD, *hD, *lD;

// defines blas_threads and blas_blocks
#include "../lib/blas_param.h"

extern double3 *dd_reduce;

void setPrec(ColorSpinorParam &param, const QudaPrecision precision)
{
  param.precision = precision;
  if (Nspin == 1 || precision == QUDA_DOUBLE_PRECISION) {
    param.fieldOrder = QUDA_FLOAT2_FIELD_ORDER;
  } else {
    param.fieldOrder = QUDA_FLOAT4_FIELD_ORDER;
  }
}


// returns true if the specified kernel performs a reduction
bool isReduction(int kernel)
{
  return (kernel >= 17);
}


void initFields(int prec)
{
  // precisions used for the source field in the copyCuda() benchmark
  QudaPrecision high_aux_prec;
  QudaPrecision low_aux_prec;

  ColorSpinorParam param;
  param.fieldLocation = QUDA_CPU_FIELD_LOCATION;
  param.nColor = 3;
  param.nSpin = Nspin; // =1 for staggered, =2 for coarse Dslash, =4 for 4d spinor
  param.nDim = 4; // number of spacetime dimensions

  param.pad = 0; // padding must be zero for cpu fields
  param.siteSubset = QUDA_PARITY_SITE_SUBSET;
  if (param.siteSubset == QUDA_PARITY_SITE_SUBSET) param.x[0] = LX/2;
  else param.x[0] = LX;
  param.x[1] = LY;
  param.x[2] = LZ;
  param.x[3] = LT;

  param.siteOrder = QUDA_EVEN_ODD_SITE_ORDER;
  param.gammaBasis = QUDA_DEGRAND_ROSSI_GAMMA_BASIS;
  param.precision = QUDA_DOUBLE_PRECISION;
  param.fieldOrder = QUDA_SPACE_SPIN_COLOR_FIELD_ORDER;

  param.create = QUDA_ZERO_FIELD_CREATE;

  vH = new cpuColorSpinorField(param);
  wH = new cpuColorSpinorField(param);
  xH = new cpuColorSpinorField(param);
  yH = new cpuColorSpinorField(param);
  zH = new cpuColorSpinorField(param);
  hH = new cpuColorSpinorField(param);
  lH = new cpuColorSpinorField(param);

  vH->Source(QUDA_RANDOM_SOURCE);
  wH->Source(QUDA_RANDOM_SOURCE);
  xH->Source(QUDA_RANDOM_SOURCE);
  yH->Source(QUDA_RANDOM_SOURCE);
  zH->Source(QUDA_RANDOM_SOURCE);
  hH->Source(QUDA_RANDOM_SOURCE);
  lH->Source(QUDA_RANDOM_SOURCE);

  // Now set the parameters for the cuda fields
  param.pad = 0; //LX*LY*LZ/2;
  
  if (param.nSpin == 4) param.gammaBasis = QUDA_UKQCD_GAMMA_BASIS;
  param.fieldLocation = QUDA_CUDA_FIELD_LOCATION;
  param.create = QUDA_ZERO_FIELD_CREATE;

  switch(prec) {
  case 0:
    setPrec(param, QUDA_HALF_PRECISION);
    high_aux_prec = QUDA_DOUBLE_PRECISION;
    low_aux_prec = QUDA_SINGLE_PRECISION;
    break;
  case 1:
    setPrec(param, QUDA_SINGLE_PRECISION);
    high_aux_prec = QUDA_DOUBLE_PRECISION;
    low_aux_prec = QUDA_HALF_PRECISION;
    break;
  case 2:
    setPrec(param, QUDA_DOUBLE_PRECISION);
    high_aux_prec = QUDA_SINGLE_PRECISION;
    low_aux_prec = QUDA_HALF_PRECISION;
    break;
  }

  vD = new cudaColorSpinorField(param);
  checkCudaError();

  wD = new cudaColorSpinorField(param);
  xD = new cudaColorSpinorField(param);
  yD = new cudaColorSpinorField(param);
  zD = new cudaColorSpinorField(param);

  setPrec(param, high_aux_prec);
  hD = new cudaColorSpinorField(param);

  setPrec(param, low_aux_prec);
  lD = new cudaColorSpinorField(param);

  // check for successful allocation
  checkCudaError();

  *vD = *vH;
  *wD = *wH;
  *xD = *xH;
  *yD = *yH;
  *zD = *zH;
  *hD = *hH;
  *lD = *lH;
}


void freeFields()
{

  // release memory
  delete vD;
  delete wD;
  delete xD;
  delete yD;
  delete zD;
  delete hD;
  delete lD;

  // release memory
  delete vH;
  delete wH;
  delete xH;
  delete yH;
  delete zH;
  delete hH;
  delete lH;
}


double benchmark(int kernel, int niter) {

  double a, b, c;
  Complex a2, b2, c2;

  cudaEvent_t start, end;
  cudaEventCreate(&start);
  cudaEventRecord(start, 0);
  cudaEventSynchronize(start);

  for (int i=0; i < niter; ++i) {

    switch (kernel) {

    case 0:
      copyCuda(*yD, *hD);
      break;

    case 1:
      copyCuda(*yD, *lD);
      break;
      
    case 2:
      axpbyCuda(a, *xD, b, *yD);
      break;

    case 3:
      xpyCuda(*xD, *yD);
      break;

    case 4:
      axpyCuda(a, *xD, *yD);
      break;

    case 5:
      xpayCuda(*xD, a, *yD);
      break;

    case 6:
      mxpyCuda(*xD, *yD);
      break;

    case 7:
      axCuda(a, *xD);
      break;

    case 8:
      caxpyCuda(a2, *xD, *yD);
      break;

    case 9:
      caxpbyCuda(a2, *xD, b2, *yD);
      break;

    case 10:
      cxpaypbzCuda(*xD, a2, *yD, b2, *zD);
      break;

    case 11:
      axpyBzpcxCuda(a, *xD, *yD, b, *zD, c);
      break;

    case 12:
      axpyZpbxCuda(a, *xD, *yD, *zD, b);
      break;

    case 13:
      caxpbypzYmbwCuda(a2, *xD, b2, *yD, *zD, *wD);
      break;
      
    case 14:
      cabxpyAxCuda(a, b2, *xD, *yD);
      break;

    case 15:
      caxpbypzCuda(a2, *xD, b2, *yD, *zD);
      break;

    case 16:
      caxpbypczpwCuda(a2, *xD, b2, *yD, c2, *zD, *wD);
      break;

    case 17:
      caxpyXmazCuda(a2, *xD, *yD, *zD);
      break;

    case 18:
      caxpyXmazDDCuda(*xD, *yD, *zD);
      break;

      // double
    case 19:
      normCuda(*xD);
      break;

    case 20:
      reDotProductCuda(*xD, *yD);
      break;

    case 21:
      axpyNormCuda(a, *xD, *yD);
      break;

    case 22:
      xmyNormCuda(*xD, *yD);
      break;
      
    case 23:
      caxpyNormCuda(a2, *xD, *yD);
      break;

    case 24:
      caxpyXmazNormXCuda(a2, *xD, *yD, *zD);
      break;

    case 25:
      cabxpyAxNormCuda(a, b2, *xD, *yD);
      break;

    // double2
    case 26:
      cDotProductCuda(*xD, *yD);
      break;

    case 27:
      xpaycDotzyCuda(*xD, a, *yD, *zD);
      break;
      
    case 28:
      caxpyDotzyCuda(a2, *xD, *yD, *zD);
      break;

    // double3
    case 29:
      cDotProductNormACuda(*xD, *yD);
      break;

    case 30:
      cDotProductNormBCuda(*xD, *yD);
      break;

    case 31:
      caxpbypzYmbwcDotProductUYNormYCuda(a2, *xD, b2, *yD, *zD, *wD, *vD);
      break;

    case 32:
      cDotProductNormALocalCuda(*xD, *yD);
      break;

    default:
      errorQuda("Undefined blas kernel %d\n", kernel);
    }
  }
  
  cudaEventCreate(&end);
  cudaEventRecord(end, 0);
  cudaEventSynchronize(end);
  float runTime;
  cudaEventElapsedTime(&runTime, start, end);
  cudaEventDestroy(start);
  cudaEventDestroy(end);

  double secs = runTime / 1000;
  return secs;
}

#define ERROR(a) fabs(norm2(*a##D) - norm2(*a##H)) / norm2(*a##H)

double test(int kernel) {

  double a = 1.5, b = 2.5, c = 3.5;
  Complex a2(a, b), b2(b, -c), c2(a+b, c*a);
  double error = 0;

  switch (kernel) {

  case 0:
    *hD = *hH;
    copyCuda(*yD, *hD);
    copyCpu(*yH, *hH);
    error = ERROR(y);
    break;

  case 1:
    *lD = *lH;
    copyCuda(*yD, *lD);
    copyCpu(*yH, *lH);
    error = ERROR(y);
    break;
      
  case 2:
    *xD = *xH;
    *yD = *yH;
    axpbyCuda(a, *xD, b, *yD);
    axpbyCpu(a, *xH, b, *yH);
    error = ERROR(y);
    break;

  case 3:
    *xD = *xH;
    *yD = *yH;
    xpyCuda(*xD, *yD);
    xpyCpu(*xH, *yH);
    error = ERROR(y);
    break;

  case 4:
    *xD = *xH;
    *yD = *yH;
    axpyCuda(a, *xD, *yD);
    axpyCpu(a, *xH, *yH);
    error = ERROR(y);
    break;

  case 5:
    *xD = *xH;
    *yD = *yH;
    xpayCuda(*xD, a, *yD);
    xpayCpu(*xH, a, *yH);
    error = ERROR(y);
    break;

  case 6:
    *xD = *xH;
    *yD = *yH;
    mxpyCuda(*xD, *yD);
    mxpyCpu(*xH, *yH);
    error = ERROR(y);
    break;

  case 7:
    *xD = *xH;
    axCuda(a, *xD);
    axCpu(a, *xH);
    error = ERROR(x);
    break;

  case 8:
    *xD = *xH;
    *yD = *yH;
    caxpyCuda(a2, *xD, *yD);
    caxpyCpu(a2, *xH, *yH);
    error = ERROR(y);
    break;

  case 9:
    *xD = *xH;
    *yD = *yH;
    caxpbyCuda(a2, *xD, b2, *yD);
    caxpbyCpu(a2, *xH, b2, *yH);
    error = ERROR(y);
    break;

  case 10:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    cxpaypbzCuda(*xD, a2, *yD, b2, *zD);
    cxpaypbzCpu(*xH, a2, *yH, b2, *zH);
    error = ERROR(z);
    break;

  case 11:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    axpyBzpcxCuda(a, *xD, *yD, b, *zD, c);
    axpyBzpcxCpu(a, *xH, *yH, b, *zH, c);
    error = ERROR(x) + ERROR(y);
    break;

  case 12:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    axpyZpbxCuda(a, *xD, *yD, *zD, b);
    axpyZpbxCpu(a, *xH, *yH, *zH, b);
    error = ERROR(x) + ERROR(y);
    break;

  case 13:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    *wD = *wH;
    caxpbypzYmbwCuda(a2, *xD, b2, *yD, *zD, *wD);
    caxpbypzYmbwCpu(a2, *xH, b2, *yH, *zH, *wH);
    error = ERROR(z) + ERROR(y);
    break;
      
  case 14:
    *xD = *xH;
    *yD = *yH;
    cabxpyAxCuda(a, b2, *xD, *yD);
    cabxpyAxCpu(a, b2, *xH, *yH);
    error = ERROR(y) + ERROR(x);
    break;

   case 15:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    {caxpbypzCuda(a2, *xD, b2, *yD, *zD);
      caxpbypzCpu(a2, *xH, b2, *yH, *zH);
      error = ERROR(z); }
    break;
    
  case 16:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    *wD = *wH;
    {caxpbypczpwCuda(a2, *xD, b2, *yD, c2, *zD, *wD);
      caxpbypczpwCpu(a2, *xH, b2, *yH, c2, *zH, *wH);
      error = ERROR(w); }
    break;

  case 17:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    {caxpyXmazCuda(a2, *xD, *yD, *zD);
      caxpyXmazCpu(a2, *xH, *yH, *zH);
      error = ERROR(y) + ERROR(x); }
    break;

  case 18:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    {double3 d = make_double3(real(a2), imag(a2), 1.0);
      cudaMemcpy(dd_reduce, &d, sizeof(double3), cudaMemcpyHostToDevice);
      caxpyXmazDDCuda(*xD, *yD, *zD);
      caxpyXmazCpu(a2, *xH, *yH, *zH);
      error = ERROR(y) + ERROR(x); }
    break;

    // double
  case 19:
    *xD = *xH;
    error = fabs(normCuda(*xD) - normCpu(*xH)) / normCpu(*xH);
    break;
    
  case 20:
    *xD = *xH;
    *yD = *yH;
    error = fabs(reDotProductCuda(*xD, *yD) - reDotProductCpu(*xH, *yH)) / fabs(reDotProductCpu(*xH, *yH));
    break;

  case 21:
    *xD = *xH;
    *yD = *yH;
    {double d = axpyNormCuda(a, *xD, *yD);
    double h = axpyNormCpu(a, *xH, *yH);
    error = ERROR(y) + fabs(d-h)/fabs(h);}
    break;

  case 22:
    *xD = *xH;
    *yD = *yH;
    {double d = xmyNormCuda(*xD, *yD);
    double h = xmyNormCpu(*xH, *yH);
    error = ERROR(y) + fabs(d-h)/fabs(h);}
    break;
    
  case 23:
    *xD = *xH;
    *yD = *yH;
    {double d = caxpyNormCuda(a, *xD, *yD);
    double h = caxpyNormCpu(a, *xH, *yH);
    error = ERROR(y) + fabs(d-h)/fabs(h);}
    break;

  case 24:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    {double d = caxpyXmazNormXCuda(a, *xD, *yD, *zD);
      double h = caxpyXmazNormXCpu(a, *xH, *yH, *zH);
      error = ERROR(y) + ERROR(x) + fabs(d-h)/fabs(h);}
    break;

  case 25:
    *xD = *xH;
    *yD = *yH;
    {double d = cabxpyAxNormCuda(a, b2, *xD, *yD);
      double h = cabxpyAxNormCpu(a, b2, *xH, *yH);
      error = ERROR(x) + ERROR(y) + fabs(d-h)/fabs(h);}
    break;

    // double2
  case 26:
    *xD = *xH;
    *yD = *yH;
    error = abs(cDotProductCuda(*xD, *yD) - cDotProductCpu(*xH, *yH)) / abs(cDotProductCpu(*xH, *yH));
    break;
    
  case 27:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    { Complex d = xpaycDotzyCuda(*xD, a, *yD, *zD);
      Complex h = xpaycDotzyCpu(*xH, a, *yH, *zH);
      error =  fabs(norm2(*yD) - norm2(*yH)) / norm2(*yH) + abs(d-h)/abs(h);
    }
    break;
    
  case 28:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    {Complex d = caxpyDotzyCuda(a, *xD, *yD, *zD);
      Complex h = caxpyDotzyCpu(a, *xH, *yH, *zH);
    error = ERROR(y) + abs(d-h)/abs(h);}
    break;

    // double3
  case 29:
    *xD = *xH;
    *yD = *yH;
    { double3 d = cDotProductNormACuda(*xD, *yD);
      double3 h = cDotProductNormACpu(*xH, *yH);
      error = fabs(d.x - h.x) / fabs(h.x) + fabs(d.y - h.y) / fabs(h.y) + fabs(d.z - h.z) / fabs(h.z); }
    break;
    
  case 30:
    *xD = *xH;
    *yD = *yH;
    { double3 d = cDotProductNormBCuda(*xD, *yD);
      double3 h = cDotProductNormBCpu(*xH, *yH);
      error = fabs(d.x - h.x) / fabs(h.x) + fabs(d.y - h.y) / fabs(h.y) + fabs(d.z - h.z) / fabs(h.z); }
    break;
    
  case 31:
    *xD = *xH;
    *yD = *yH;
    *zD = *zH;
    *wD = *wH;
    *vD = *vH;
    { double3 d = caxpbypzYmbwcDotProductUYNormYCuda(a2, *xD, b2, *yD, *zD, *wD, *vD);
      double3 h = caxpbypzYmbwcDotProductUYNormYCpu(a2, *xH, b2, *yH, *zH, *wH, *vH);
      error = ERROR(z) + ERROR(y) + fabs(d.x - h.x) / fabs(h.x) + 
	fabs(d.y - h.y) / fabs(h.y) + fabs(d.z - h.z) / fabs(h.z); }
    break;

  case 32:
    *xD = *xH;
    *yD = *yH;
    { cDotProductNormALocalCuda(*xD, *yD);
      double3 d;
      cudaMemcpy(&d, dd_reduce, sizeof(double3), cudaMemcpyDeviceToHost);
      double3 h = cDotProductNormACpu(*xH, *yH);
      error = fabs(d.x - h.x) / fabs(h.x) + fabs(d.y - h.y) / fabs(h.y) + fabs(d.z - h.z) / fabs(h.z); }
    break;
    
  default:
    errorQuda("Undefined blas kernel %d\n", kernel);
  }

  return error;
}

void write(const char *names[], int threads[][3], int blocks[][3])
{
  printf("\nWriting optimal parameters to blas_param.h\n");

  FILE *fp = fopen("blas_param.h", "w");
  fprintf(fp, "//\n// Auto-tuned blas CUDA parameters, generated by blas_test\n//\n\n");

  fprintf(fp, "static int blas_threads[%d][3] = {\n", Nkernels);

  for (int i=0; i<Nkernels; i++) {
    fprintf(fp, "  {%4d, %4d, %4d}%c  // Kernel %2d: %s\n", threads[i][0], threads[i][1], threads[i][2],
	    ((i == Nkernels-1) ? ' ' : ','), i, names[i]);
  }
  fprintf(fp, "};\n\n");

  fprintf(fp, "static int blas_blocks[%d][3] = {\n", Nkernels);

  for (int i=0; i<Nkernels; i++) {
    fprintf(fp, "  {%5d, %5d, %5d}%c  // Kernel %2d: %s\n", blocks[i][0], blocks[i][1], blocks[i][2],
	    ((i == Nkernels-1) ? ' ' : ','), i, names[i]);
  }
  fprintf(fp, "};\n");

  fclose(fp);
}


int main(int argc, char** argv)
{

  int ndim=4, dims[] = {1, 1, 1, 1};
  initCommsQuda(argc, argv, dims, ndim);

  int dev = 0;
  if (argc == 2) dev = atoi(argv[1]);
  initQuda(dev);

  const char *names[] = {
    "copyCuda (high source precision)",
    "copyCuda (low source precision)",
    "axpbyCuda",
    "xpyCuda",
    "axpyCuda",
    "xpayCuda",
    "mxpyCuda",
    "axCuda",
    "caxpyCuda",
    "caxpbyCuda",
    "cxpaypbzCuda",
    "axpyBzpcxCuda",
    "axpyZpbxCuda",
    "caxpbypzYmbwCuda",
    "cabxpyAxCuda",
    "caxpbypzCuda",
    "caxpbypczpwCuda",
    "caxpyXmazCuda",
    "caxpyXmazDDCuda",
    "normCuda",
    "reDotProductCuda",
    "axpyNormCuda",
    "xmyNormCuda",
    "caxpyNormCuda",
    "caxpyXmazNormXCuda",
    "cabxpyAxNormCuda",
    "cDotProductCuda",
    "xpaycDotzyCuda",
    "caxpyDotzyCuda",
    "cDotProductNormACuda",
    "cDotProductNormBCuda",
    "caxpbypzYmbwcDotProductWYNormYCuda",
    "cDotProductNormALocalCuda",
  };

  const char *prec_str[] = {"half", "single", "double"};
  
  // Only benchmark double precision if supported
#if (__CUDA_ARCH__ >= 130)
  int Nprec = 3;
#else
  int Nprec = 2;
#endif

  int niter = Niter;

  // turn off error checking in blas kernels for tuning
  setBlasTuning(QUDA_TUNE_YES);

  for (int prec = 0; prec < Nprec; prec++) {

    printf("\nBenchmarking %s precision with %d iterations...\n\n", prec_str[prec], niter);
    initFields(prec);

    for (int kernel = 0; kernel < Nkernels; kernel++) {

      double gflops_max = 0.0;
      double gbytes_max = 0.0;
      int threads_max = 0; 
      int blocks_max = 0;

      cudaError_t error;

      // only benchmark "high precision" copyCuda() if double is supported
      if ((Nprec < 3) && (kernel == 0)) continue;

      for (unsigned int thread = ThreadMin; thread <= ThreadMax; thread+=32) {

	// for reduction kernels, the number of threads must be a power of two
	if (isReduction(kernel) && (thread & (thread-1))) continue;

	for (unsigned int grid = GridMin; grid <= GridMax; grid *= 2) {
	  setBlasParam(kernel, prec, thread, grid);
	  
	  // first do warmup run
	  benchmark(kernel, 1);
	  
	  blas_quda_flops = 0;
	  blas_quda_bytes = 0;

	  double secs = benchmark(kernel, niter);
	  error = cudaGetLastError();
	  double flops = blas_quda_flops;
	  double bytes = blas_quda_bytes;
	  
	  double gflops = (flops*1e-9)/(secs);
	  double gbytes = bytes/(secs*(1<<30));

	  // prevents selection of failed parameters
	  if (gbytes > gbytes_max && error == cudaSuccess) { 
	    gflops_max = gflops;
	    gbytes_max = gbytes;
	    threads_max = thread;
	    blocks_max = grid;
	  }
	  //printf("%d %d %-35s %f s, flops = %e, Gflop/s = %f, GiB/s = %f\n", 
	  //	 thread, grid, names[kernel], secs, flops, gflops, gbytes);
	}
      }

      if (threads_max == 0) {
	errorQuda("Autotuning failed for %s kernel: %s", names[kernel], cudaGetErrorString(error));
      } else {
	// now rerun with more iterations to get accurate speed measurements
	setBlasParam(kernel, prec, threads_max, blocks_max);
	benchmark(kernel, 1);
	blas_quda_flops = 0;
	blas_quda_bytes = 0;
	
	double secs = benchmark(kernel, 100*niter);
	
	gflops_max = (blas_quda_flops*1e-9)/(secs);
	gbytes_max = blas_quda_bytes/(secs*(1<<30));
      }

      printf("%-35s: %4d threads per block, %5d blocks per grid, Gflop/s = %8.4f, GiB/s = %8.4f\n", 
	     names[kernel], threads_max, blocks_max, gflops_max, gbytes_max);

      blas_threads[kernel][prec] = threads_max;
      blas_blocks[kernel][prec] = blocks_max;
    }
    freeFields();

    // halve the number of iterations for the next precision
    niter /= 2; 
    if (niter==0) niter = 1;
  }

  // clear the error state
  cudaGetLastError();

  // turn on error checking in blas kernels
  setBlasTuning(QUDA_TUNE_NO);

  // lastly check for correctness
  for (int prec = 0; prec < Nprec; prec++) {
    printf("\nTesting %s precision...\n\n", prec_str[prec]);
    initFields(prec);
    
    for (int kernel = 0; kernel < Nkernels; kernel++) {
      // only benchmark "high precision" copyCuda() if double is supported
      if ((Nprec < 3) && (kernel == 0)) continue;
      double error = test(kernel);
      printfQuda("%-35s error = %e, \n", names[kernel], error);
    }
    freeFields();
  }

  write(names, blas_threads, blas_blocks);

  endQuda();

  endCommsQuda();
}

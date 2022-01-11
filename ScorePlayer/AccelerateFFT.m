//
//  accelerateFFT.m
//  ScorePlayer
//
//  Created by Aaron Wyatt on 11/05/2016.
//  Copyright (c) 2016 Decibel. All rights reserved.
//

#import "AccelerateFFT.h"

@implementation AccelerateFFT {
    FFTSetup fftSetup;
    UInt32 nSamples;
    vDSP_Length log2nSamples;
    UInt32 nOver2;
    Float32 fftNormFactor;
    COMPLEX_SPLIT A;
}

@synthesize nSamples;

- (id)initForNumberOfSamples:(UInt32)n
{
    self = [super init];
    
    //First, check that our number of samples is a power of two.
    if ((n == 0) || ((n & (n - 1)) != 0)) {
        return nil;
    }
    
    nSamples = n;
    log2nSamples = log2(nSamples);
    nOver2 = nSamples / 2;
    fftSetup = vDSP_create_fftsetup(log2nSamples, FFT_RADIX2);
    fftNormFactor = 1.0 / (2 * nSamples);
    
    //Allocate space for the real and imaginary parts of our complex array.
    A.realp = (Float32 *)malloc(nOver2 * sizeof(Float32));
    A.imagp = (Float32 *)malloc(nOver2 * sizeof(Float32));
    
    return self;
}

- (UInt32)getBufferSize
{
    return nOver2 * sizeof(Float32);
}

- (BOOL)performFFTOnSamples:(Float32 *)samples numberOfSamples:(UInt32)n withOutput:(Float32 *)output outputSize:(UInt32)outputSize
{
    //Check that we have the right number of samples and output size.
    if ((n != nSamples) || (outputSize != sizeof(Float32) * nOver2)) {
        return NO;
    }
    
    //Convert our array of samples to a complex array.
    vDSP_ctoz((COMPLEX *)samples, 2, &A, 1, nOver2);
    
    //Perform our FFT. (Results are returned in place in our complex array.)
    vDSP_fft_zrip(fftSetup, &A, 1, log2nSamples, FFT_FORWARD);
    
    //Scale our FFT.
    vDSP_vsmul(A.realp, 1, &fftNormFactor, A.realp, 1, nOver2);
    vDSP_vsmul(A.imagp, 1, &fftNormFactor, A.imagp, 1, nOver2);
    
    //Then get the absolute values of our vectors, and place this in our output buffer.
    vDSP_zvabs(&A, 1, output, 1, nOver2);
    
    return YES;
}

- (void)dealloc
{
    vDSP_destroy_fftsetup(fftSetup);
    free(A.realp);
    free(A.imagp);
}

@end

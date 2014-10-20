#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdint.h>

#include "tsc.h"
#ifndef BUFLEN
#define BUFLEN 4096
#endif

// only 32 bits!
//#define rdtscll(val) __asm__ __volatile__("rdtsc" : "=A" (val))
// from http://en.wikipedia.org/wiki/RDTSC
inline uint64_t rdtsc() {
	  uint32_t lo, hi;
	   /* We cannot use "=A", since this would use %rax on x86_64 */
	    __asm__ __volatile__ ("rdtsc" : "=a" (lo), "=d" (hi));
	      return (uint64_t)hi << 32 | lo;
}


struct timeval tsc_delta2tv(uint64_t then, uint64_t now)
{
	static unsigned long Hz=0;
	uint64_t diff = then-now;
	double tmp;
	struct timeval tv;
	if(Hz==0) 	// needs init
	{
		char buf[BUFLEN];
		float MHz=-1.0;
		FILE * f = fopen("/proc/cpuinfo","r");
		while(fgets(buf,BUFLEN-1,f)!=NULL)
		{
			if(sscanf(buf,"cpu MHz		: %f",&MHz)>0)
				break;
		}
		if(MHz == -1.0)
		{
			fprintf(stderr,"Error: tsc_delta2tv:: the 'cpu MHz' not found in /proc/cpuinfo\n");
			abort();
		}
		fclose(f);
		Hz=MHz*1000000;	// should this be 1024*1024!?  I don't think so, but don't know
	}
	if(diff==0)		// don't do a divide by zero :-)
	{
		tv.tv_sec=0;
		tv.tv_usec=0;
	}
	else
	{
		tmp = (double)Hz/(double)diff;		// compute inverse for better float precision
		tmp = 1/tmp;				// now flip it over
		tv.tv_sec = floor(tmp);
		tv.tv_usec = floor((tmp-floor(tmp))*1000000);	// usec = 10^-6
	}
	return tv;
}






// Original Email from "Pavlos Papageorgiou" <pavlos@eng.umd.edu> -- thanks Pavlos!
#if 0
> Get current TSC into nanosec.
> linux/arch/i386/kernel/tsc.c:107
> 
> /*
>  *          * Scheduler clock - returns current time in nanosec units.
>  *                   */
> unsigned long long sched_clock(void)
> {
> 	unsigned long long this_offset;
> 
> 	/*
> 	 *                  * in the NUMA case we dont use the TSC as they are not
> 	 *                                   * synchronized across all CPUs.
> 	 *                                                    */
> #ifndef CONFIG_NUMA
> 	if (!cpu_khz || check_tsc_unstable())
> 		/* no locking but a rare wrong value is not a big deal */
> 		return (jiffies_64 - INITIAL_JIFFIES) * (1000000000 / HZ);
> 
> 	/* read the Time Stamp Counter: */
> 	rdtscll(this_offset);
> 
> 	/* return the value in ns */
> 	return cycles_2_ns(this_offset);
> }
> 
> The rdtscll reads the TSC
> linux/include/asm-i386/msr.h:71
> 
> #define rdtscll(val) \
> __asm__ __volatile__("rdtsc" : "=A" (val))
> 
> 
> And the cycles are translated into nanosec units.
> linux/arch/i386/kernel/tsc.c:107
> 
> static unsigned long cyc2ns_scale __read_mostly;
> 
> #define CYC2NS_SCALE_FACTOR 10 /* 2^10, carefully chosen */
> 
> static inline void set_cyc2ns_scale(unsigned long cpu_khz)
> {
> 	cyc2ns_scale = (1000000 << CYC2NS_SCALE_FACTOR)/cpu_khz;
> }
> 
> static inline unsigned long long cycles_2_ns(unsigned long long cyc)
> {
> 	return (cyc * cyc2ns_scale) >> CYC2NS_SCALE_FACTOR;
> }
> 
> 
> So the whole point is to set cyc2ns_scale and cpu_khz.
> This happens in tsc_init().
> linux/arch/i386/kernel/tsc.c:195
> 
> void tsc_init(void)
> {
> 	if (!cpu_has_tsc || tsc_disable)
> 		return;
> 
> 	cpu_khz = calculate_cpu_khz();
> 	tsc_khz = cpu_khz;
> 
> 	if (!cpu_khz)
> 		return;
> 
> 	printk("Detected %lu.%03lu MHz processor.\n",
> 			(unsigned long)cpu_khz / 1000,
> 			(unsigned long)cpu_khz % 1000);
> 
> 	set_cyc2ns_scale(cpu_khz);
> 	use_tsc_delay();
> }
> 
> This cpu_khz is a global kernel variable and is exported by
> /proc/cpuinfo accurately.
> linux/arch/i386/kernel/cpu/proc.c:99
> 
> static int show_cpuinfo(struct seq_file *m, void *v)
> {
> 	...
> 		if ( cpu_has(c, X86_FEATURE_TSC) ) {
> 			unsigned int freq = cpufreq_quick_get(n);
> 			if (!freq)
> 				freq = cpu_khz;
> 			seq_printf(m, "cpu MHz\t\t: %u.%03u\n",
> 					freq / 1000, (freq % 1000));
> 		}
> 	...
> }
> 
> Here is how you calculate cpu_khz, but it is already exported by cpuinfo.
> linux/arch/i386/kernel/tsc.c:128
> 
> static unsigned long calculate_cpu_khz(void)
> {
> 	unsigned long long start, end;
> 	unsigned long count;
> 	u64 delta64;
> 	int i;
> 	unsigned long flags;
> 
> 	local_irq_save(flags);
> 
> 	/* run 3 times to ensure the cache is warm */
> 	for (i = 0; i < 3; i++) {
> 		mach_prepare_counter();
> 		rdtscll(start);
> 		mach_countup(&count);
> 		rdtscll(end);
> 	}
> 	/*
> 	 *                  * Error: ECTCNEVERSET
> 	 *                                   * The CTC wasn't reliable: we got a hit on the very first read,
> 	 *                                                    * or the CPU was so fast/slow that the quotient wouldn't fit in
> 	 *                                                                     * 32 bits..
> 	 *                                                                                      */
> 	if (count <= 1)
> 		goto err;
> 
> 	delta64 = end - start;
> 
> 	/* cpu freq too fast: */
> 	if (delta64 > (1ULL<<32))
> 		goto err;
> 
> 	/* cpu freq too slow: */
> 	if (delta64 <= CALIBRATE_TIME_MSEC)
> 		goto err;
> 
> 	delta64 += CALIBRATE_TIME_MSEC/2; /* round for do_div */
> 	do_div(delta64,CALIBRATE_TIME_MSEC);
> 
> 	local_irq_restore(flags);
> 	return (unsigned long)delta64;
> err:
> 	local_irq_restore(flags);
> 	return 0;
> }
#endif

#include <config.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include "radix.h"

struct patricia_table *policies;

static in_addr_t addr_from_octets(unsigned int o1, unsigned int o2, 
                                  unsigned int o3, unsigned int o4){
  return (htonl((o1<<24) + (o2<<16) + (o3<<8) + o4));
}



int main(int argc, char *argv[]) {
  FILE *blfp = fopen(argv[1], "r");
  char line[512];
  unsigned int len, o1, o2, o3, o4, filter_off;
  policies = patricia_new();

  if(blfp == NULL) {
    exit(EXIT_FAILURE);
  }
    
  while( fgets( line, 512, blfp ) != NULL ) { /* blacklist. */
    char *hash = index(line, '#');
    if ( hash != NULL ) {
      hash[0]='\n'; hash[1]='\0'; /* strip hash comments */
    }
    if (hash != line) {
      /* no comment on the line, or something before the comment, print. */
      
        if(sscanf(line, "%u.%u.%u.%u/%u %n",
                  &o1, &o2, &o3, &o4, &len, &filter_off) >= 5) { /* 5 or 6 is ok, apparently
                                                                    handling %n is nonuniform */
          // log_print(LOG_DEBUG, "destpol: %s" /* has newline */, prefix_filter);
          /* this inserted policy might be implicated in a leak 1/14/07 */
          patricia_insert(policies, addr_from_octets(o1,o2,o3,o4), (unsigned char)len, (void *)1);
        }
    } /* else, its a comment line. (hash is right where line begins.) */
  }
  (void) fclose(blfp);

  while ( fgets(line, 512, stdin)  ) { /* testme list */
    if(sscanf(line, "%u.%u.%u.%u", &o1, &o2, &o3, &o4) >= 4) { 
      if (patricia_lookup(policies, addr_from_octets(o1, o2, o3, o4))) {
        fprintf(stderr, "(stderr) dropping %s", line);
      } else {
        fputs(line, stdout);
      }
    }
  }
  exit(EXIT_SUCCESS);
}
  





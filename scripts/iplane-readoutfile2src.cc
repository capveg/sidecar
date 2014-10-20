#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

void truncate_error(char *filename) {
	fprintf(stderr, "File %s incomplete\n", filename);
	fflush(stderr);
	exit(1);
}

int main(int argc, char **argv)
{
    FILE *fp;
    int clientId, uniqueId, sz, len;
    
    if (argc < 2) {
	fprintf(stderr, "usage: readoutfile filename\n");
	truncate_error(argv[1]);
    }

    for(int fileIndex=1;fileIndex<argc;fileIndex++)
    {
	    fp = fopen(argv[fileIndex], "r");

	    while (1) {
		if (fread(&clientId, sizeof(int), 1, fp) != 1)
			break;
		if (fread(&uniqueId, sizeof(int), 1, fp) != 1)
			truncate_error(argv[1]);
		if (fread(&sz, sizeof(int), 1, fp) != 1)
			truncate_error(argv[1]);
		if (fread(&len, sizeof(int), 1, fp) != 1)
			truncate_error(argv[1]);

		/*	printf("read %d records (%d bytes) from %d %d\n", sz, len, clientId, uniqueId); */
		for (int i=0; i<sz; i++) {
		    struct in_addr ip;
		    int hops;
		    int ttl;
		    if (fread(&ip, sizeof(struct in_addr), 1, fp) != 1)
				truncate_error(argv[1]);
		    if (fread(&hops, sizeof(int), 1, fp) != 1)
				truncate_error(argv[1]);
		    printf("%s\n", inet_ntoa(ip));
		    for (int j=0; j<hops; j++) {
			float lat;
			if (fread(&ip, sizeof(struct in_addr), 1, fp) != 1)
				truncate_error(argv[1]);
			if (fread(&lat, sizeof(float), 1, fp) != 1)
				truncate_error(argv[1]);
			if (fread(&ttl, sizeof(int), 1, fp) != 1)
				truncate_error(argv[1]);
			if (ttl > 512) {
				fprintf(stderr, "File %s possibly corrupted\n", argv[1]);
				fflush(stderr);
				exit(1);
			}
		    }
		}
	    }
	    fclose(fp);
    }
    return 0;
}

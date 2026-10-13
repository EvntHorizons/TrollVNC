#include "Runner.h"
#include <spawn.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>
#include <stdio.h>
#include <string.h>
extern char **environ;
char *fc_run(const char *path, const char *argument) {
    int pipes[2]; if(pipe(pipes)) return strdup("Unable to open output pipe.");
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions,pipes[1],1);
    posix_spawn_file_actions_adddup2(&actions,pipes[1],2);
    posix_spawn_file_actions_addclose(&actions,pipes[0]);
    posix_spawn_file_actions_addclose(&actions,pipes[1]);
    posix_spawnattr_t attr; posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETPGROUP); posix_spawnattr_setpgroup(&attr,0);
    char *args[]={(char *)path,(char *)argument,NULL};
    char *openArgs[]={(char *)path,"--bundleid",(char *)argument,NULL};
    pid_t pid; int err=posix_spawn(&pid,path,&actions,&attr,strcmp(path,"/var/jb/usr/bin/uiopen")==0?openArgs:args,environ);
    posix_spawnattr_destroy(&attr);posix_spawn_file_actions_destroy(&actions);close(pipes[1]);
    if(err){close(pipes[0]);return strdup(strerror(err));}
    fcntl(pipes[0],F_SETFL,O_NONBLOCK);
    size_t used=0; char *out=calloc(65536,1);int status=0;time_t start=time(NULL);int ended=0;
    while(!ended){
        char chunk[2048];ssize_t n=read(pipes[0],chunk,sizeof(chunk));
        if(n>0 && used<64000){size_t take=(size_t)n;if(take>64000-used)take=64000-used;memcpy(out+used,chunk,take);used+=take;}
        if(time(NULL)-start>=15){kill(-pid,SIGKILL);waitpid(pid,&status,0);strcpy(out+used,"\nStopped after 15 seconds.\n");used=strlen(out);ended=1;}
        else if(waitpid(pid,&status,WNOHANG)==pid){
            while((n=read(pipes[0],chunk,sizeof(chunk)))>0 && used<64000){size_t take=(size_t)n;if(take>64000-used)take=64000-used;memcpy(out+used,chunk,take);used+=take;}ended=1;
        }
        else usleep(20000);
    }
    close(pipes[0]);snprintf(out+used,65536-used,"\n[exit status %d]\n",WIFEXITED(status)?WEXITSTATUS(status):-1);return out;
}

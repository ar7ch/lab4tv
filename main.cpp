#include <iostream>
#include <sched.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <fstream>

/// Source: https://cesarvr.io/post/2018-05-22-create-containers/

int TRY(int status, const char *msg) {
    if(status == -1) {
        perror(msg);
        exit(EXIT_FAILURE);
    }
    return status;
}

//void write_rule(const char* path, const char* value) {
//    int fp = open(path, O_WRONLY | O_APPEND );
//    write(fp, value, strlen(value));
//    close(fp);
//}

#define CGROUP_FOLDER "/sys/fs/cgroup/pids/container/"
#define concat(a,b) (a"" b)
void cgroup_init() {
//    mkdir( CGROUP_FOLDER, S_IRUSR | S_IWUSR);  // Read & Write
//    const char* pid  = std::to_string(getpid()).c_str();
//
//    write_rule(concat(CGROUP_FOLDER, "pids.max"), "5");
//    write_rule(concat(CGROUP_FOLDER, "notify_on_release"), "1");
//    write_rule(concat(CGROUP_FOLDER, "cgroup.procs"), pid);
}

char* get_stack_memory() {
    const int stackSize = 65536;
    auto *stack = new (std::nothrow) char[stackSize];

    if (stack == nullptr) {
        printf("Cannot allocate memory \n");
        exit(EXIT_FAILURE);
    }

    return stack+stackSize;  //move the pointer to the end of the array because the stack grows backward.
}

void set_hostname(std::string hostname) {
    sethostname(hostname.c_str(), hostname.size());
}

void setup_env_vars() {
    clearenv();
    setenv("TERM", "xterm-256color", 0);
    setenv("PATH", "/bin/:/sbin/:usr/bin:/usr/sbin", 0);
    set_hostname("container");
}

int run_shell(void*) {
    char *args[] = {(char *)"/bin/bash", (char *)NULL};
    execvp(args[0], args);
    return 0;
}

void setup_root_dir(const char* folder){
    chroot(folder);
    chdir("/");
}

void clone_process(int (*fn)(void*), int flags){
    auto pid = TRY(clone(fn, get_stack_memory(), flags, 0), "clone" );
    wait(nullptr);
}

void mount_proc() {
    mount("proc", "/proc", "proc", 0, 0);
}

void container_init() {
    cgroup_init();
    setup_env_vars();
    setup_root_dir("./container/container_root");
    mount_proc();
}

void container_deinit() {
    umount("/proc");
}

void container_run_shell() {
    clone_process(run_shell, SIGCHLD);
}

int start_container(void *args) {
    container_init();
    container_run_shell();
    container_deinit();
    return EXIT_SUCCESS;
}

int main() {
    clone_process(start_container, CLONE_NEWPID | CLONE_NEWUTS | SIGCHLD | CLONE_NEWNET | CLONE_NEWNS);
    return EXIT_SUCCESS;
}
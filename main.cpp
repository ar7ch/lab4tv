#include <iostream>
#include <sched.h>
#include <cstring>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <fcntl.h>

#define CGROUP_DIR "/sys/fs/cgroup/pids/container/"
#define concat(a,b) (a"" b)

/// Sources:
/// https://cesarvr.io/post/2018-05-22-create-containers/


void cgroup_write(const char* path, const char* value) {
    int fp = open(path, O_WRONLY | O_APPEND );
    write(fp, value, strlen(value));
    close(fp);
}

void cgroup_init() {
    mkdir(CGROUP_DIR, S_IRUSR | S_IWUSR);  // Read & Write
    auto pid_str = std::to_string(getpid());
    cgroup_write(concat(CGROUP_DIR, "pids.max"), "15");
    cgroup_write(concat(CGROUP_DIR, "notify_on_release"), "1");
    cgroup_write(concat(CGROUP_DIR, "cgroup.procs"), pid_str.c_str());
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
    if (sethostname(hostname.c_str(), hostname.size()) == -1) {
        throw std::runtime_error("sethostname failed: " + std::string(strerror(errno)));
    }
}

void setup_env_vars() {
    clearenv();
    setenv("TERM", "xterm-256color", 0);
    setenv("PATH", "/bin/:/sbin/:usr/bin:/usr/sbin", 0);
    set_hostname("container");
}

int run_shell(void*) {
    char *args[] = {(char *)"/bin/bash", (char *)NULL};
    if (execvp(args[0], args) == -1) {
        throw std::runtime_error("execvp failed: " + std::string(strerror(errno)));
    }
    return 0;
}

void setup_root_dir(std::string& folder){
    int ret = chroot(folder.c_str());
    if (ret != 0) {
        throw std::runtime_error("chroot failed: " + std::string(strerror(errno)));
    }
    ret = chdir("/");
    if (ret != 0) {
        throw std::runtime_error("chdir failed: " + std::string(strerror(errno)));
    }
}

void clone_process(int (*fn)(void*), int flags){
    auto pid = clone(fn, get_stack_memory(), flags, 0);
    if (pid < 0) {
        throw std::runtime_error("clone failed: " + std::string(strerror(errno)));
    }
    wait(nullptr);
}

#define NETNS_PATH "/var/run/netns/container_network_ns"

void join_network_namespace() {
    int ns_fd = open(NETNS_PATH, O_RDONLY);
    if (ns_fd == -1) {
        throw std::runtime_error("open network namespace failed: " + std::string(strerror(errno)));
    }
    if (setns(ns_fd, CLONE_NEWNET) == -1) {
        close(ns_fd);
        throw std::runtime_error("setns failed: " + std::string(strerror(errno)));
    }
    close(ns_fd);
}

void mount_system_fs() {
    if (mount("none", "/proc", "proc", 0, nullptr) != 0) {
        throw std::runtime_error("mount /proc failed: " + std::string(strerror(errno)));
    }
    if (mount("none", "/sys", "sysfs", 0, nullptr) != 0) {
        throw std::runtime_error("mount /sys failed: " + std::string(strerror(errno)));
    }
}

void container_init(std::string root_dir="./container/container_root") {
    cgroup_init();
    setup_env_vars();
    join_network_namespace();
    setup_root_dir(root_dir);
    mount_system_fs();
}

void container_deinit() {
    umount("/proc");
    umount("/sys");
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
    int container_clone_flags = CLONE_NEWPID | CLONE_NEWUTS | SIGCHLD | CLONE_NEWNS;
    std::cout << "starting container" << std::endl;
    clone_process(start_container, container_clone_flags);
    return EXIT_SUCCESS;
}
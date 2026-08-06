#include <linux/uinput.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

static int fd;

static void emit(int type, int code, int val) {
    struct input_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = type; ev.code = code; ev.value = val;
    if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) {
        perror("write"); exit(1);
    }
}

static void synth_sync(void) { emit(EV_SYN, SYN_REPORT, 0); }

static void mouse_button(int code, int press) {
    emit(EV_KEY, code, press);
    synth_sync();
    if (!press) usleep(20000);
}

static void rel_move(int dx, int dy) {
    int step = 30;
    int nx = abs(dx), ny = abs(dy);
    int n = (nx > ny ? nx : ny);
    if (n == 0) return;
    int i;
    for (i = 0; i <= n; i += step) {
        int sx = (dx > 0 ? step : -step);
        int sy = (dy > 0 ? step : -step);
        if (i + step > n) { sx = (dx > 0 ? dx - i : -(-dx - i)); sy = (dy > 0 ? dy - i : -(-dy - i)); }
        emit(EV_REL, REL_X, sx);
        emit(EV_REL, REL_Y, sy);
        synth_sync();
        usleep(2000);
    }
}

static int key_code(const char *name) {
    if (!strcmp(name, "menu")) return KEY_MENU;
    if (!strcmp(name, "enter")) return KEY_ENTER;
    if (!strcmp(name, "esc")) return KEY_ESC;
    if (!strcmp(name, "right")) return KEY_RIGHT;
    if (!strcmp(name, "left")) return KEY_LEFT;
    if (!strcmp(name, "down")) return KEY_DOWN;
    if (!strcmp(name, "up")) return KEY_UP;
    if (!strcmp(name, "tab")) return KEY_TAB;
    if (!strcmp(name, "space")) return KEY_SPACE;
    if (!strcmp(name, "home")) return KEY_HOME;
    if (!strcmp(name, "f5")) return KEY_F5;
    if (!strcmp(name, "ctrlleft")) return KEY_LEFTCTRL;
    if (!strcmp(name, "ctrlright")) return KEY_RIGHTCTRL;
    if (!strcmp(name, "shiftleft")) return KEY_LEFTSHIFT;
    if (!strcmp(name, "shiftright")) return KEY_RIGHTSHIFT;
    if (!strcmp(name, "altleft")) return KEY_LEFTALT;
    if (!strcmp(name, "altright")) return KEY_RIGHTALT;
    if (!strcmp(name, "superleft")) return KEY_LEFTMETA;
    if (!strcmp(name, "backspace")) return KEY_BACKSPACE;
    if (!strcmp(name, "delete")) return KEY_DELETE;
    if (!strcmp(name, "insert")) return KEY_INSERT;
    if (!strcmp(name, "end")) return KEY_END;
    if (!strcmp(name, "pageup")) return KEY_PAGEUP;
    if (!strcmp(name, "pagedown")) return KEY_PAGEDOWN;
    if (!strcmp(name, "0")) return KEY_0;
    if (!strcmp(name, "1")) return KEY_1;
    if (!strcmp(name, "2")) return KEY_2;
    if (!strcmp(name, "3")) return KEY_3;
    if (!strcmp(name, "4")) return KEY_4;
    if (!strcmp(name, "5")) return KEY_5;
    if (!strcmp(name, "6")) return KEY_6;
    if (!strcmp(name, "7")) return KEY_7;
    if (!strcmp(name, "8")) return KEY_8;
    if (!strcmp(name, "9")) return KEY_9;
    return atoi(name);
}

static void do_key(int code, int press) {
    emit(EV_KEY, code, press);
    synth_sync();
    usleep(50000);
}

static int run_cmd(int argc, char **argv) {
    if (getenv("UINPUTCTL_DEBUG")) {
        int i;
        fprintf(stderr, "cmd:");
        for (i = 0; i < argc; i++) fprintf(stderr, " %s", argv[i]);
        fprintf(stderr, "\n");
    }
    if (argc < 2) return 1;
    const char *a = argv[1];
    if (!strcmp(a, "absraw") && argc >= 4) {
        emit(EV_ABS, ABS_X, atoi(argv[2]));
        emit(EV_ABS, ABS_Y, atoi(argv[3]));
        synth_sync();
        return 0;
    } else if (!strcmp(a, "rel") && argc >= 4) {
        rel_move(atoi(argv[2]), atoi(argv[3]));
        return 0;
    } else if (!strcmp(a, "click") && argc >= 3) {
        int btn = !strcmp(argv[2], "right") ? BTN_RIGHT : !strcmp(argv[2], "middle") ? BTN_MIDDLE : BTN_LEFT;
        mouse_button(btn, 1);
        usleep(60000);
        mouse_button(btn, 0);
        return 0;
    } else if (!strcmp(a, "keydown") && argc >= 3) {
        do_key(key_code(argv[2]), 1);
        return 0;
    } else if (!strcmp(a, "keyup") && argc >= 3) {
        do_key(key_code(argv[2]), 0);
        return 0;
    } else if (!strcmp(a, "key") && argc >= 3) {
        do_key(key_code(argv[2]), 1);
        do_key(key_code(argv[2]), 0);
        return 0;
    } else if (!strcmp(a, "chord") && argc >= 3) {
        int n = argc - 2, i;
        for (i = 0; i < n; i++) emit(EV_KEY, key_code(argv[i + 2]), 1);
        synth_sync();
        usleep(100000);
        for (i = 0; i < n; i++) emit(EV_KEY, key_code(argv[i + 2]), 0);
        synth_sync();
        return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s [serve fifo] | absraw X Y | rel dx dy | click btn | keydown key | keyup key | key key | chord k...\n", argv[0]); return 1; }

    struct uinput_setup us;
    memset(&us, 0, sizeof(us));
    snprintf(us.name, UINPUT_MAX_NAME_SIZE, "uinputctl");
    us.id.bustype = BUS_USB;
    us.id.vendor = 0x1234;
    us.id.product = 0x5678;

    fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) { perror("open /dev/uinput"); return 1; }

    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_EVBIT, EV_REL);
    ioctl(fd, UI_SET_EVBIT, EV_ABS);
    ioctl(fd, UI_SET_KEYBIT, BTN_LEFT);
    ioctl(fd, UI_SET_KEYBIT, BTN_RIGHT);
    ioctl(fd, UI_SET_KEYBIT, BTN_MIDDLE);
    ioctl(fd, UI_SET_RELBIT, REL_X);
    ioctl(fd, UI_SET_RELBIT, REL_Y);

    {
        int k;
        for (k = 1; k <= 250; k++) ioctl(fd, UI_SET_KEYBIT, k);
    }

    struct uinput_abs_setup ax = { .code = ABS_X, .absinfo = { .minimum = 0, .maximum = 32767, .flat = 0 } };
    struct uinput_abs_setup ay = { .code = ABS_Y, .absinfo = { .minimum = 0, .maximum = 32767, .flat = 0 } };
    ioctl(fd, UI_ABS_SETUP, &ax);
    ioctl(fd, UI_ABS_SETUP, &ay);

    const char *settle_env = getenv("UINPUTCTL_SETTLE_MS");
    const char *drain_env = getenv("UINPUTCTL_DRAIN_MS");
    int settle_ms = settle_env ? atoi(settle_env) : 300;
    int drain_ms = drain_env ? atoi(drain_env) : 20;

    ioctl(fd, UI_DEV_SETUP, &us);
    if (ioctl(fd, UI_DEV_CREATE) < 0) { perror("UI_DEV_CREATE"); return 1; }
    usleep(settle_ms * 1000);

    if (!strcmp(argv[1], "serve")) {
        if (argc < 3) { fprintf(stderr, "serve needs a fifo path\n"); return 1; }
        /* Open O_RDWR so our own write end keeps the FIFO from ever hitting
         * EOF when the trigger closes its end between presses. */
        int fifo = open(argv[2], O_RDWR | O_NONBLOCK);
        if (fifo < 0) { perror("open fifo"); ioctl(fd, UI_DEV_DESTROY); close(fd); return 1; }
        char carry[512];
        int clen = 0;
        char buf[512];
        while (1) {
            ssize_t got = read(fifo, buf, sizeof(buf));
            if (got < 0) {
                if (errno == EAGAIN) { usleep(20000); continue; }
                break;
            }
            if (got == 0) { usleep(20000); continue; }
            buf[got] = 0;
            char *line = buf;
            while (line && *line) {
                char *nl = strchr(line, '\n');
                if (!nl) {
                    /* incomplete trailing line: carry it over */
                    if (clen + (int)strlen(line) < (int)sizeof(carry) - 1) {
                        memcpy(carry + clen, line, strlen(line));
                        clen += (int)strlen(line);
                        carry[clen] = 0;
                    }
                    break;
                }
                *nl = 0;
                char *cmd = line;
                if (clen > 0) {
                    memcpy(carry + clen, cmd, strlen(cmd));
                    clen += (int)strlen(cmd);
                    carry[clen] = 0;
                    cmd = carry;
                }
                char *tok[16];
                int ntok = 0;
                char *p = cmd;
                while (p && ntok < 16) {
                    while (*p == ' ' || *p == '\t') p++;
                    if (!*p) break;
                    tok[ntok++] = p;
                    while (*p && *p != ' ' && *p != '\t') p++;
                    if (*p) *p++ = 0;
                }
                if (ntok > 0) run_cmd(ntok, tok);
                clen = 0;
                line = nl + 1;
            }
        }
        ioctl(fd, UI_DEV_DESTROY);
        close(fd);
        return 0;
    }

    if (run_cmd(argc, argv)) {
        fprintf(stderr, "bad args\n");
        ioctl(fd, UI_DEV_DESTROY);
        close(fd);
        return 1;
    }
    usleep(drain_ms * 1000);
    ioctl(fd, UI_DEV_DESTROY);
    close(fd);
    return 0;
}

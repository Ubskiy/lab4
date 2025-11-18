#!/usr/bin/env bash
# ЛР4. Анализ файловой системы преподавателя (labfiles-25)
# Разработчик: Батаев А.И.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/labfiles-25"

CIRCUS_DIR="$BASE_DIR/Цирковое_Дело"
CIRCUS_TESTS_DIR="$CIRCUS_DIR/tests"

POP_DIR="$BASE_DIR/Поп-Культуроведение"
POP_TESTS_DIR="$POP_DIR/tests"

STUDENTS_GROUPS_DIR="$BASE_DIR/students/groups"

error() {
    echo "ОШИБКА: $*" >&2
}

press_enter() {
    echo
    read -rp "Нажмите Enter, чтобы продолжить..." _
}

check_fs() {
    local ok=1

    if [[ ! -d "$BASE_DIR" ]]; then
        error "Не найдена директория labfiles-25 по пути: $BASE_DIR"
        ok=0
    fi

    if [[ ! -d "$CIRCUS_TESTS_DIR" ]]; then
        error "Не найдена директория с тестами по Цирковому делу: $CIRCUS_TESTS_DIR"
        ok=0
    fi

    if [[ ! -d "$POP_TESTS_DIR" ]]; then
        echo "ВНИМАНИЕ: не найдена директория с тестами по Поп-Культуроведению: $POP_TESTS_DIR"
        echo "Базовый функционал будет работать только с Цирковым делом."
    fi

    if [[ ! -d "$STUDENTS_GROUPS_DIR" ]]; then
        error "Не найдена директория со списками групп: $STUDENTS_GROUPS_DIR"
        ok=0
    fi

    if (( ok == 0 )); then
        exit 1
    fi
}

list_groups() {
    if [[ ! -d "$STUDENTS_GROUPS_DIR" ]]; then
        return
    fi
    echo "Доступные группы:"
    ls "$STUDENTS_GROUPS_DIR" | sed 's/^/ - /'
}

group_exists() {
    local grp="$1"
    [[ -f "$STUDENTS_GROUPS_DIR/$grp" ]]
}

get_all_test_files() {
    local files=()
    shopt -s nullglob

    if [[ -d "$CIRCUS_TESTS_DIR" ]]; then
        files+=( "$CIRCUS_TESTS_DIR"/TEST-* )
    fi

    if [[ -d "$POP_TESTS_DIR" ]]; then
        files+=( "$POP_TESTS_DIR"/TEST-* )
    fi

    shopt -u nullglob

    if ((${#files[@]} == 0)); then
        return 1
    fi

    printf '%s\n' "${files[@]}"
    return 0
}

get_circus_test_files() {
    local files=()
    shopt -s nullglob
    files+=( "$CIRCUS_TESTS_DIR"/TEST-* )
    shopt -u nullglob

    if ((${#files[@]} == 0)); then
        return 1
    fi

    printf '%s\n' "${files[@]}"
    return 0
}

# --------------------
# 1) Лучший студент по оценке
# --------------------
best_by_mark_count() {
    local group="$1"
    local mark="$2"

    if [[ ! "$mark" =~ ^[345]$ ]]; then
        error "Оценка должна быть 3, 4 или 5, а не \"$mark\"."
        return 1
    fi

    if ! group_exists "$group"; then
        error "Группа \"$group\" не найдена в $STUDENTS_GROUPS_DIR"
        echo
        list_groups
        return 1
    fi

    TEST_FILES=()
    while IFS= read -r file; do
        TEST_FILES+=("$file")
    done < <(get_all_test_files)

    if ((${#TEST_FILES[@]} == 0)); then
        error "Не найдено ни одного файла с тестами."
        return 1
    fi

    echo "Лучший студент группы $group по количеству оценок $mark"

    local best_student=""
    local best_count="0"

    read best_student best_count < <(
        awk -F';' -v grp="$group" -v wanted="$mark" '
            {
                m = $5
                gsub(/[^0-9]/, "", m)
                if (m == "") next

                if ($1 == grp && m == wanted) {
                    cnt[$2]++
                }
            }
            END {
                max = 0
                best = ""
                for (s in cnt) {
                    if (cnt[s] > max) {
                        max = cnt[s]
                        best = s
                    }
                }
                if (best == "") {
                    print "NO_DATA 0"
                } else {
                    print best, max
                }
            }
        ' "${TEST_FILES[@]}"
    )

    if [[ "$best_student" == "NO_DATA" || -z "$best_student" ]]; then
        echo "Для группы $group нет оценок $mark в тестах."
        return 0
    fi

    echo "Лучший студент: $best_student (кол-во оценок $mark: $best_count)"
    echo
    echo "Подробные строки по этому студенту и оценке $mark:"

    awk -F';' -v grp="$group" -v wanted="$mark" -v st="$best_student" '
        {
            m = $5
            gsub(/[^0-9]/, "", m)
            if (m == "") next

            if ($1 == grp && m == wanted && $2 == st) {
                printf "Группа: %-8s Студент: %-20s Файл: %-25s Правильных ответы: %-3s Оценка: %s\n", \
                       $1, $2, FILENAME, $4, m
            }
        }
    ' "${TEST_FILES[@]}"
}

# --------------------
# 2) Лучшая посещаемость за период + выбор предмета
# --------------------
best_attendance_for_period() {
    local group="$1"
    local from_l="$2"
    local to_l="$3"
    local subject_choice="$4"

    if ! group_exists "$group"; then
        error "Группа \"$group\" не найдена."
        echo
        list_groups
        return 1
    fi

    if [[ ! "$from_l" =~ ^[0-9]+$ || ! "$to_l" =~ ^[0-9]+$ ]]; then
        error "Номера занятий должны быть целыми числами."
        return 1
    fi

    if (( from_l > to_l )); then
        echo "ВНИМАНИЕ: начало периода больше конца. Меняю местами."
        local tmp="$from_l"
        from_l="$to_l"
        to_l="$tmp"
    fi

    case "$subject_choice" in
        1)
            attendance_file="$CIRCUS_DIR/${group}-attendance"
            ;;
        2)
            attendance_file="$POP_DIR/${group}-attendance"
            ;;
        *)
            error "Некорректный выбор предмета: $subject_choice"
            return 1
            ;;
    esac

    if [[ ! -f "$attendance_file" ]]; then
        error "Файл посещаемости не найден: $attendance_file"
        return 1
    fi

    echo "Лучшая посещаемость группы $group с занятия $from_l по $to_l"

    awk -v from="$from_l" -v to="$to_l" '
        {
            name = $1
            bits = $2
            if (bits == "") next

            if (NR == 1) {
                maxlen = length(bits)
                if (to > maxlen) to = maxlen
            }

            present = 0
            for (i = from; i <= to; i++) {
                if (substr(bits, i, 1) == "1") present++
            }
            cnt[name] = present
        }
        END {
            max = -1
            for (s in cnt) if (cnt[s] > max) max = cnt[s]

            print "Максимальное присутствий: " max
            print "Студенты:"        
            for (s in cnt) if (cnt[s] == max) printf " - %s (%d)\n", s, cnt[s]
        }
    ' "$attendance_file"
}

# --------------------
# 3) Лучшие по Цирковому делу
# --------------------
best_students_circus() {
    echo "Лучшие студенты по предмету \"Цирковое дело\""

    CFILES=()
    while IFS= read -r file; do
        CFILES+=("$file")
    done < <(get_circus_test_files)

    if ((${#CFILES[@]} == 0)); then
        error "Нет файлов тестов по Цирковому делу."
        return 1
    fi

    awk -F';' '
        {
            m = $5
            gsub(/[^0-9]/, "", m)
            if (m == "") next
            mark = m + 0
            key = $2
            sum[key] += mark
            cnt[key]++
        }
        END {
            maxavg = -1
            for (s in cnt) {
                avg = sum[s]/cnt[s]
                if (avg > maxavg) maxavg = avg
            }

            printf "Максимальный средний балл: %.2f\n", maxavg
            print "Студенты:"            
            for (s in cnt) {
                avg = sum[s]/cnt[s]
                if (avg == maxavg) printf " - %s (%.2f)\n", s, avg
            }
        }
    ' "${CFILES[@]}"
}

# --------------------
# 4) Средняя оценка студента
# --------------------
avg_mark_for_student_subject() {
    local student="$1"
    local subject_choice="$2"

    local subj_name=""
    TFILES=()

    case "$subject_choice" in
        1)
            subj_name="Цирковое дело"
            while IFS= read -r file; do
                TFILES+=("$file")
            done < <(get_circus_test_files)
            ;;
        2)
            subj_name="Поп-Культуроведение"
            if [[ -d "$POP_TESTS_DIR" ]]; then
                shopt -s nullglob
                for f in "$POP_TESTS_DIR"/TEST-*; do
                    TFILES+=("$f")
                done
                shopt -u nullglob
            fi
            ;;
        *)
            error "Некорректный выбор предмета"
            return 1
            ;;
    esac

    if ((${#TFILES[@]} == 0)); then
        error "Нет тестов по предмету \"$subj_name\""
        return 1
    fi

    echo "Средняя оценка студента $student по предмету $subj_name"

    awk -F';' -v st="$student" '
        {
            m = $5
            gsub(/[^0-9]/, "", m)
            mark = m + 0
            if ($2 == st && mark > 0 && mark <= 5) {
                sum += mark
                cnt++
            }
        }
        END {
            if (cnt == 0) {
                print "Нет данных"
                exit
            }
            printf "Средняя: %.2f (оценок: %d)\n", sum/cnt, cnt
        }
    ' "${TFILES[@]}"
}

# --------------------
# Главное меню
# --------------------
main_menu() {
    check_fs

    while true; do
        echo
        echo "Выберите действие:"
        echo " 1) Лучший студент группы по количеству 5/4/3"
        echo " 2) Лучшая посещаемость группы за период занятий"
        echo " 3) Лучшие студенты по Цирковому делу"
        echo " 4) Средняя оценка студента по предмету"
        echo " 5) Показать список групп"
        echo " 0) Выход"
        read -rp "Ваш выбор: " choice

        case "$choice" in
            1)
                list_groups
                read -rp "Введите код группы: " group
                read -rp "Введите оценку (3/4/5): " mark
                echo
                best_by_mark_count "$group" "$mark"
                press_enter
                ;;

            2)
                list_groups
                read -rp "Введите код группы: " group
                read -rp "Номер занятия ОТ: " from_l
                read -rp "Номер занятия ДО: " to_l
                echo "Выберите предмет:"
                echo " 1) Цирковое дело"
                echo " 2) Поп-Культуроведение"
                read -rp "Ваш выбор: " subject_choice
                echo
                best_attendance_for_period "$group" "$from_l" "$to_l" "$subject_choice"
                press_enter
                ;;

            3)
                best_students_circus
                press_enter
                ;;

            4)
                read -rp "Введите логин студента: " student
                echo "Выберите предмет:"                read -rp "Ваш выбор (1/2): " subj_choice
                echo
                avg_mark_for_student_subject "$student" "$subj_choice"
                press_enter
                ;;

            5)
                list_groups
                press_enter
                ;;

            0)
                echo "Выход."
                exit 0
                ;;

            *)
                echo "Неверный пункт меню."
                ;;
        esac
    done
}

main_menu



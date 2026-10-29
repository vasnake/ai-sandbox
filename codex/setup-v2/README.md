# 2026-10-09 setup-v2

Первая версия была не очень удачная, две основные проблемы
- GID:UID пользователя dev в контейнере не матчится с овнером файлов в воркспейсе, который mount с хоста.
- нет докер-композ файла, неудобно управлять, в частности, подключить в сеть к уже существующим контейнерам (clickhouse)

The setup provides:
- Ubuntu 24.04, Codex, Git/SSH, Python/venv, and basic build tools.
- dev with vlk’s actual UID/GID, without changing host repository ownership.
- Your host repository directory mounted read/write at /workspace.
- The existing airflow-network, declared external.
- 16 GiB RAM limit—a ceiling, not a reservation. Docker Docs
- Persistent Codex credentials, configuration, and history in a named volume.
- run codex with danger-full-access with on-request approvals, retaining Docker’s default security policies.

bootstrap: generate '.env', build image and start 'codex' conainer in detached mode
```sh
pushd ${HOME:?unknown}/data/github/ai-sandbox/codex/setup-v2
export PROJECT_ROOT=${HOME:?unknown}/data/gitlab/gameram # && pushd ${PROJECT_ROOT:?unknown} # workdir useful

# build and start
bash -x ./bootstrap.sh ${PROJECT_ROOT:?unknown}
```

how to use it after it is ready
```sh
# manage container
docker compose ps # stop # start # exec codex bash
docker compose stop
docker compose start
# docker compose down # destroy container
# 'down' preserves the Codex state volume; 'down -v' deletes it.
# Exiting an interactive shell leaves the container running.

# run session
docker compose start
docker compose exec codex bash

# in container
pushd /workspace/gameram-dwh # data
pushd /workspace/data # gameram-dwh
codex
```

## login

логин через чат, как в версии1
```sh
codex login

# Open the printed sign-in link in your host browser. If the redirect to
# http://127.0.0.1:1455/auth/callback?code=ac_...Xq0
# fails, copy the COMPLETE callback URL from the browser's address bar.
# Open a second host terminal in the Compose directory

docker compose exec codex bash
read -r -s -p 'Paste full callback URL: ' callback_url
printf '\n'
curl --noproxy '*' --silent --show-error "$callback_url"
codex login status

```

## first session
```sh
docker compose exec codex bash
pushd /workspace/gameram-dwh
codex
```

## results

Great, just as I want it.

Есть rw доступ к файлам проектов: маппинг UID, GID работает.
Может использовать 'clickhouse-exp' хост для доступа к КХ бд: docker сеть работает.

Copy from codex window problem: use shift to bypass app hooks
> Shift + mouse drag, then Ctrl+Shift+C, uses your host terminal’s selection and clipboard

`/raw on`
> This enables raw scrollback mode, which the official OpenAI documentation describes as making terminal selection and copying easier.

# 2026-10-12 cleanup

Remove unused docker images

current image: `codex-dev:ubuntu24-v2`
```sh
docker ps -a | grep codex
# 28be4693c741   codex-sandbox                                "bash"                   5 days ago     Exited (0) 4 days ago                  codex-sandbox-session1
docker rm 28be4693c741

docker image ls | grep codex
codex-dev:ubuntu24-v2                                                                            d5060b257577       1.27GB          333MB   U
codex-sandbox-debug:latest                                                                       6ebd87418b3a        2.3GB          635MB
codex-sandbox-session1-261007v1:latest                                                           796d9c9ae09f       4.24GB         1.19GB
codex-sandbox:latest                                                                             064944147a44       1.34GB          349MB

docker image ls --format '{{.Repository}}:{{.Tag}}' | \
  grep '^codex-sandbox' | \
  xargs -r echo docker image rm

```

# 2026-10-28 Code review session

Q:
in this session we will perform a code review ... First, remind me, please, what principles should we use for this task?

A:
We should use these principles:

  • Review against develop from the merge base: git diff develop...feature/BACK-2533-friendships-metrics-config-service. Start by listing modified components.
  • Use code and GitLab CI/CD as the source of truth. Read relevant README and AGENTS.md files, but verify documentation against the implementation.
  • Check consistency across components: config keys, job arguments, schemas, artifact paths, dependencies, and orchestration.
  • Assess correctness and maintainability: modularity, readability, DRY, KISS, encapsulation, testability, and potential performance problems.
  • Prioritize actionable findings. Explain the trigger, impact, and location; distinguish confirmed defects from external prerequisites and optional improvements. Avoid unsupported performance claims.
  • Validate in the project’s environment. Use the prescribed runtime and uv where applicable; report checks performed and any limitations.
  • Keep tracked files unchanged during the review.
  • Respect the release process: missing version or changelog updates are not findings at this stage. External infrastructure may live elsewhere; its absence here alone does not establish a defect.

  We’ll discuss the review in English.

Q: go

A:
The MR changes two components: the ETL Scala job and its deployed YAML configuration (8 files total).
It switches friendship metrics to config-service experiment assignments on a configured date and adds three tests.
I’m checking assignment semantics, historical-date handling, and compatibility with downstream metrics consumers.

One concern needs closer attention: config-service assignments include an explicit treatment flag,
but the new metrics conversion retains only the experiment name and variant ID.

I couldn’t run the tests: compilation is blocked by HTTP 401 when Gradle downloads the private config-lib:1.0.0 dependency. I’m continuing with static checks; the local runtime is the required Amazon Corretto 17.

I found one correctness concern:
  • [P2] Treatment/control information is lost during conversion. In MetricsProvider.scala (etl/src/main/scala/com/gameram/batch/metrics/common/metricsProvider/MetricsProvider.scala:235), assignments are reduced to name and variantId, discarding
    treatment. Config-service supports multiple rules with different treatment variants, so a variant ID alone cannot reliably identify treatment versus control. The shared assigner already returns the authoritative flag. Preserve it in the
    properties map—for example, "treatment" -> userExperiment.treatment.toString—and cover a multi-rule case.

Two smaller improvements:
  • Test coverage: the new tests exercise the switch date, allow lists, and region rules. Add an after-switch case and assert legacy experiment assignments before the switch—the existing legacy test explicitly excludes userExperiments from
    comparison.
  • DRY: snapshot loading and definition validation duplicate UserExperimentsConfigServiceBuilder.scala
  (etl/src/main/scala/com/gameram/batch/entities/user/experiments/configservice/builder/UserExperimentsConfigServiceBuilder.scala:28).
  A shared loader would help keep both consumers consistent, but this is optional.

## fixes

> I couldn’t run the tests:

вышел в консоль (ctrl-c), скачал либу, обнулил токен, запустил кодекс снова
```sh
export GITLAB_PERSONAL_ACCESS_TOKEN=glpat-***p24
./gradlew shadowJar --info
./gradlew :etl:test --tests "com.gameram.streaming.LfgIndexUpdateJobTest" --fail-fast --info # --rerun
export GITLAB_PERSONAL_ACCESS_TOKEN=
```

тесты работают, интеграционные (с testcontainers) не работают. Потом будем разбираться.

> [P2] Treatment/control information is lost during conversion

The assignment is calculated correctly, but the conversion into metric properties discards part of its result. A user’s variantId does not universally tell us whether they belong to treatment or control.
```scala
The shared UserExperimentAssigner.scala (etl/src/main/scala/com/gameram/batch/entities/user/experiments/configservice/builder/UserExperimentAssigner.scala:32)
preserves both values returned by config-lib:

  variantId = Option(value.variantId()).map(_.intValue()),
  treatment = value.treatment()

However, MetricsProvider.scala (etl/src/main/scala/com/gameram/batch/metrics/common/metricsProvider/MetricsProvider.scala:235) converts that assignment into:

  Map(
    "name" -> userExperiment.experimentName,
    "variantId" -> userExperiment.variantId.map(_.toString).getOrElse("")
  )

  treatment disappears at this point and is absent from the resulting metric.

  Why that matters: variantId identifies a hash bucket. For a partition-based rule, config-lib determines treatment by comparing that bucket with that rule’s configured variant:

  treatment = variantId == rule.variant

  Consequently, 0 does not inherently mean control, and 1 does not inherently mean treatment.

  For example, consider one experiment with two rules, both using modulo = 2 and covering all partitions:

   Rule condition    Configured treatment variant    User’s variantId    Actual assignment
  ━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━
   Country = RU                                 1                   0    Control
  ────────────────  ──────────────────────────────  ──────────────────  ───────────────────
   Country = BR                                 0                   0    Treatment

  Both assignments become the same experiment properties:

  {
    "name": "Experiment.Salt",
    "variantId": "0"
  }

  The explicit distinction between control and treatment has been lost. Recovering it downstream would require the relevant historical rule configuration and enough user context to reproduce rule selection.

  Rule selection also matters: I checked the actual config-lib:1.0.0 bytecode. It returns the first treatment assignment found across applicable rules; if none exists, it returns the first control assignment. Preserving the library’s final
  treatment result avoids reimplementing that logic downstream.

  Allow-list assignments are another special case: config-lib returns variantId = null and treatment = true. The conversion currently stores only variantId = "". That case can be interpreted using a special convention, but an explicit flag makes
  the meaning directly available.

  The minimal fix is to retain both fields:

  val experimentProperties = Map(
    "name" -> userExperiment.experimentName,
    "variantId" -> userExperiment.variantId.map(_.toString).getOrElse(""),
    "treatment" -> userExperiment.treatment.toString
  )
```

> DRY: snapshot loading and definition validation duplicate UserExperimentsConfigServiceBuilder.scala

```scala
The new UserFriendshipsMetricsBuilder.scala
(etl/src/main/scala/com/gameram/batch/metrics/common/pipelines/userFriendships/UserFriendshipsMetricsBuilder.scala:88)
repeats the loading block already present in UserExperimentsConfigServiceBuilder.scala
(etl/src/main/scala/com/gameram/batch/entities/user/experiments/configservice/builder/UserExperimentsConfigServiceBuilder.scala:27).

  Both perform the same sequence:

  val definitions = ExperimentDefinition.build(
    reader.readExperiments(snapshotDateTime).collect().toSeq,
    reader.readExperimentRules(snapshotDateTime).collect().toSeq,
    reader.readConditions(snapshotDateTime).collect().toSeq,
    reader.readExperimentTags(snapshotDateTime).collect().toSeq,
    reader.readTags(snapshotDateTime).collect().toSeq,
    experimentsValidFrom
  )
  definitions.foreach(_.toExperiment)

A small shared method could encapsulate the repeated sequence:

  def loadDefinitions(
      reader: ConfigServiceExperimentsReader,
      snapshotDateTime: LocalDateTime,
      experimentsValidFrom: LocalDateTime
  ): Seq[ExperimentDefinition]

  Each caller would retain responsibility for choosing its timestamp and processing its users or metrics

```

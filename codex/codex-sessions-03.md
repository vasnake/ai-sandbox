# codex, working sessions
чтобы не забыть, для пост-анализа

```sh
# host
pushd ${HOME:?unknown}/data/github/ai-sandbox/codex/setup-v2
export PROJECT_ROOT=${HOME:?unknown}/data/gitlab/gameram
docker compose start # ps # stop # start # exec codex bash
docker compose exec codex bash
# container
ls -lah
pushd /workspace/data
codex
```

## 2026-11-11 gyml-online dev session

> Next time, say “Export today’s session” or invoke $export-session-dialog

Q:

› Hi, today we will be working on 'gyml-online' project. I described the task in the file 'MLDE-654-gyml-online-auto.md', take a look


A:

• I’ll read the task file and the `gyml_online` guidance, then check the code and CI to understand the current setup.

• The existing GYML pipeline supplies user embeddings; the notebooks prepare subscription-based examples and train the online model against those embeddings. CI already builds and deploys the service, but the model preparation and training are still manual.

I also found different experiment IDs and artifact paths across the notebooks and service config. We’ll need to trace which inputs belong together before trying to reproduce a run.

• Read the task and checked the notebooks, service code, CI scripts, and upstream GYML pipeline.

The current chain is:

1. **GYML training and historical inference** produce user embeddings.
2. **Dataset notebook** combines user features, early subscriptions, recommendation events, and game intersections.
3. **Training notebook** joins those examples with GYML embeddings, trains the cold-start model, evaluates checkpoints, and exports weights plus the game dictionary.
4. **Service integration** pairs that state with compatible inference code.
5. **GitLab CI** downloads the selected state, builds and tests the Docker image, then deploys it to ECS.

The main automation gap is between GYML output and a deployable online-model artifact. Initial points to resolve:

- Notebook paths reference different experiments and personal directories.
- Training and serving duplicate transformations and model architecture.
- The service hardcodes game vocabulary size (`228`), while training derives it from data.
- Checkpoint selection and model/service version coordination remain manual.
- Existing service CI runs on repository changes; it is not connected to completion of GYML training.

I suggest first documenting the exact inputs, outputs, parameters, and runtime for each stage, then reproducing one compatible model end to end before changing orchestration.

No files changed or remote operations executed.


Q:

› OK, your findings strongly correlates with my understanding of a problem. First, lets put our findings in the doc 'MLDE-654-gyml-online-auto.md' section 'analysis'.


A:

• I’ll add an `analysis` section covering the current pipeline, automation gaps, and what still needs verification.

• Added the `analysis` section to [MLDE-654-gyml-online-auto.md](/workspace/data/MLDE-654-gyml-online-auto.md), covering the current pipeline, automation gaps, compatibility constraints, and proposed investigation sequence.

Unverified runtime and deployment details are explicitly marked. All added file links resolve.


Q:

› OK, good job! Approved and commited. Before we continue, I'd like to establish some principles considering working directories and files for current task: we will not edit notebook files in 'research', we will use them as an information source. We will be creating scripts (python, bash) in the 'ml/gyml_online/' directory. Content of this directory reflected in file 'ml/gyml_online/README.md'. OK?


A:

• Agreed. For MLDE-654:

- Keep `research/` notebooks unchanged and use them as reference.
- Create Python and Bash scripts under `ml/gyml_online/`.
- Keep `ml/gyml_online/README.md` aligned with that directory’s contents and usage.


Q:

› Perfect! Lets begin. We should define various parameters and make some decisions, right? OK, give me the full list, with references, so I can find where it defined and used


A:

• I’ll trace the parameters and manual choices through both notebooks, the service, and the GYML outputs. I’ll list where each is defined and used, and separate existing values from decisions we still need to make.

• The list includes both explicit settings and behavior embedded in functions: snapshot timing, feature encodings, game sampling, batch handling, and checkpoint selection. Two contract differences need decisions before we copy the code into scripts: the service’s locale mapping is reversed relative to training, and the service adds output noise that training evaluation does not use.

• Yes. Some items are run parameters; others are model/data contracts or operational decisions. We should distinguish them so we don’t turn every constant into a configuration option.

Below, **current values describe the checked-in code, not verified production settings**. Notebook cell numbers are zero-based; links point to the corresponding JSON lines.

**1. Run identity, upstream model, and artifact locations**

| Parameter or decision | Current definition and use | What we need to decide |
|---|---|---|
| Upstream GYML model/index | Training notebook: `index_id_historical_inference = "MLDE-621"`, `model_name_historical_inference = "exp1"`. Used to locate historical embeddings. [Training, cell 3](/workspace/data/research/gyml/online/train_gyml_online.ipynb:41), [read, cell 12](/workspace/data/research/gyml/online/train_gyml_online.ipynb:164) | Which existing GYML run will be our reproduction baseline? |
| Historical embeddings location | Notebook reads a developer-local directory. Current GYML configuration publishes under `s3://gameram-data/gyml/gnn/train/${index_id}/embeddings`. [GYML config](/workspace/data/ml/configs/config.yaml:45) | Exact S3 input, including the user dataset beneath that prefix. |
| Online training dataset location | Preparation writes under `MLDE-468-new/new_cold0d`; training downloads `MLDE-512-exp5/new_cold0d/temp_pairs4`. [Preparation, cell 7](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:78), [training download](/workspace/data/research/gyml/online/train_gyml_online.ipynb:103) | Reuse an existing prepared dataset or rebuild it? Which exact prefix? |
| Online model version | `SAVE_INDEX_ID = "MLDE-621"` determines the published model prefix. [Definition](/workspace/data/research/gyml/online/train_gyml_online.ipynb:41), [publication](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1607) | Naming convention and relationship to the upstream GYML version. |
| Local working directory | `project_prefix` is a developer-specific absolute path. It contains downloaded data, dictionaries, splits, checkpoints, and exported state. [Training, cell 3](/workspace/data/research/gyml/online/train_gyml_online.ipynb:41) | Local artifact root and separation between runs. Scripts themselves belong in `ml/gyml_online/`. |
| Intermediate names | `dataset_name`, `datasets_raw_dirname`, `model_save_dir`, `final_state_dir`, and three dictionary paths are separately constructed. [Training, cell 3](/workspace/data/research/gyml/online/train_gyml_online.ipynb:41) | Which paths should be derived from the working directory and run identity? |

The chosen online model must target the **same embedding space** as its associated GYML index. Matching vector dimensions alone is insufficient.

**2. Dataset preparation: time and population**

| Parameter or decision | Current definition and use | What we need to decide |
|---|---|---|
| Event date range | `date_from = 2026-08-01`, `date_to = 2026-09-12`; subscription and recommendation events are filtered inclusively. [Definitions](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:78), [subscriptions](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:378), [recommendations](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:520) | Baseline dates, and later how they relate to the GYML training reference time. |
| Snapshot date/hour | `str_next_date_to` selects **00:00 on the day after `date_to`**. Used for account, language, platform, and game snapshots, and recommendation schema discovery. [Definition](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:78) | Preserve this cutoff for reproduction? |
| Cold-user window | `THRESHOLD_IN_DAYS = 0`; subscriptions qualify when event date minus registration date is between zero and the threshold, inclusively. This means registration calendar day. [Definition](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:78), [filter](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:417) | Preserve registration-day users, or use another cold-user definition? |
| Subscription examples | Examples come from subscription events joined with account features. `isCrossSubscribe` is retained but not used as a filter. [Preparation, cell 28](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:417) | Preserve the event population as implemented? |
| Duplicate examples | Deduplicated by `(account_id, receiver_id)`, without specifying which event timestamp survives. [Preparation, cell 28](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:417) | Preserve arbitrary selection or define first/latest event? This affects chronological splitting. |
| Recommendation context | Recommendations are aggregated by `(account_id, receiver_id)` and joined to subscriptions using those IDs, without temporal matching. [Aggregation](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:574), [join](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:720) | Preserve this association or require a time relationship between recommendation and subscription? |
| Corrupt subscription files | Subscription reading uses `ignoreCorruptFiles=true`. [Preparation, cell 26](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:378) | Skip and report, or fail the run? |

**3. Data sources and raw features**

These are semantic choices, even where the notebook doesn’t expose a named parameter.

| Item | Current behavior and reference | Decision |
|---|---|---|
| Account features | Account S3 snapshot supplies birth date, gender, profile flags, country, registration date. [Feature expressions](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:110), [assembly](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:265) | Reproduce these sources first, or introduce the user-profile snapshot immediately? |
| Age reference date | Age uses Spark `current_date()`, rather than the selected snapshot/event date. [Feature expressions](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:110) | Which date should determine age for reproducible runs? |
| Language | `any_value(code, ignoreNulls=True)` from `account_languages`; it does not select primary language. [Preparation, cell 11](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:148) | Preserve the historical experiment or align training with the primary language supplied to serving? |
| Region | Account country is joined to `s3://gameram-data/external/regions`; the region join is inner. [Mapping source](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:195), [join](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:265) | Preserve this mapping or use profile `region_name`? |
| Platform vocabulary | `console`, `PC`, `mobile`, `XBOX`, `NINTENDO`, `PS`, `VR`; pivoted into presence flags. [Vocabulary](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:98), [pivot](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:213) | Preserve names and mapping to service platform inputs. |
| Profile games | At most **32** account games, chosen through row numbering with constant ordering. [Preparation, cell 17](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:234) | Preserve arbitrary selection or define a deterministic rule? |
| Requested/intersected games | Recommendation request games are aggregated; intersections with the receiver’s profile games produce `matching_intersected_games`. [Request games](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:574), [intersection](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:866), [final output](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:969) | Confirm that this is the intended game feature for the baseline. |
| Missing features and examples | Several joins are inner; absent game intersections can remain null after the final left join. [Account assembly](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:265), [final join](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:969) | Define which missing values exclude examples and which receive unknown-category values. |

**4. Dataset splitting, vocabulary, and sampling**

| Parameter or decision | Current definition and use | What we need to decide |
|---|---|---|
| Embedding join | Inner merge of example `receiver_id` with embedding `user`; target is `vector`. [Training, cell 14](/workspace/data/research/gyml/online/train_gyml_online.ipynb:184) | Expected schema, uniqueness of embedding users, and handling of unmatched receivers. |
| Split ordering | Sort by `dt`, `hour`, with no explicit tie-breaker. [Training, cell 15](/workspace/data/research/gyml/online/train_gyml_online.ipynb:194) | Preserve this ordering or make ties deterministic? |
| Split sizes | Last **50,000** rows are test; preceding **30,000** validation; earlier rows train. [Training, cell 17](/workspace/data/research/gyml/online/train_gyml_online.ipynb:214) | Fixed counts or another rule; behavior when the dataset is too small. |
| Game feature mode | `flag_games_intersected = True`. Selects intersected games rather than requested games. [Definition](/workspace/data/research/gyml/online/train_gyml_online.ipynb:41), [use](/workspace/data/research/gyml/online/train_gyml_online.ipynb:552) | Keep only the active mode initially, or support both? |
| Vocabulary frequency threshold | Actual calls use `THRESHOLD = 400`; `_build_dict` has an unused-in-those-calls default of `500`. Inclusion is **count > threshold**. [Definition](/workspace/data/research/gyml/online/train_gyml_online.ipynb:41), [builder](/workspace/data/research/gyml/online/train_gyml_online.ipynb:374), [calls](/workspace/data/research/gyml/online/train_gyml_online.ipynb:409) | Preserve 400 and strict comparison? |
| Vocabulary construction | Built from training data; IDs start at `2`, unknown games map to `1`; size includes two reserved slots. [Builder](/workspace/data/research/gyml/online/train_gyml_online.ipynb:374), [transformer](/workspace/data/research/gyml/online/train_gyml_online.ipynb:552) | Preserve encoding and store the exact dictionary with each model. |
| Games sampled per example | `games_to_sample=3`; Python `random.sample` selects up to three games, producing one training example per selected game. [Generator](/workspace/data/research/gyml/online/train_gyml_online.ipynb:552) | Sampling count and reproducibility. |
| Empty versus null game lists | Null becomes `[None]`; an empty array produces no generated samples. [Generator](/workspace/data/research/gyml/online/train_gyml_online.ipynb:552) | Preserve that distinction? |
| Random seeds | `torch.manual_seed(42)` is set; Python sampling has no corresponding seed in the notebook. [Torch seed](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1033), [sampling](/workspace/data/research/gyml/online/train_gyml_online.ipynb:552) | Which random sources should be seeded and recorded? |

The inactive `flag_games_intersected=False` branch also needs attention if retained: the model selects `vocab_added_games`, while generated game IDs come from `games_dict`. [Model definition](/workspace/data/research/gyml/online/train_gyml_online.ipynb:828)

**5. Training/serving feature contract and model architecture**

| Item | Existing definition | Decision |
|---|---|---|
| Active features | Age, gender, region, locale, three profile flags, six platform flags, and one game. Nickname/avatar/console are not active model inputs. [Training input keys](/workspace/data/research/gyml/online/train_gyml_online.ipynb:684), [model](/workspace/data/research/gyml/online/train_gyml_online.ipynb:828) | Preserve the active feature set for reproduction. |
| Age encoding | Boundaries: `14,18,21,24,27,30,33,36,40,45`; unknown maps to zero. [Training transformations](/workspace/data/research/gyml/online/train_gyml_online.ipynb:552), [serving](/workspace/data/gyml_online/app/inference/main.py:63) | Shared definition and versioning. |
| Gender encoding | Preparation converts strings to category IDs; training keeps those IDs. Serving converts strings to IDs separately. [Preparation](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:110), [serving](/workspace/data/gyml_online/app/inference/main.py:73) | Keep training and request transformations equivalent. |
| Region encoding | Nine named regions, unknown `1`, missing `0`. [Training transformations](/workspace/data/research/gyml/online/train_gyml_online.ipynb:552), [serving mapping](/workspace/data/gyml_online/app/inference/main.py:23) | Shared mapping and unknown handling. |
| Locale encoding | Training maps language strings to integer IDs. Service currently defines the dictionary in the reverse direction, then looks up language strings. [Training](/workspace/data/research/gyml/online/train_gyml_online.ipynb:552), [serving](/workspace/data/gyml_online/app/inference/main.py:35) | Resolve this difference explicitly; direct copying would preserve inconsistent behavior. |
| Categorical embeddings | Age `12×5`, gender `4×3`, region `11×5`, locale `26×6`, binary features `2×2`, game vocabulary `×32`. [Training model](/workspace/data/research/gyml/online/train_gyml_online.ipynb:828) | Keep as fixed baseline architecture or expose selected dimensions later. |
| Game vocabulary size | Derived during training; hardcoded to **228** in service. [Training](/workspace/data/research/gyml/online/train_gyml_online.ipynb:828), [service](/workspace/data/gyml_online/app/inference/main.py:183) | Make model loading reconstruct the correct architecture, or keep manual synchronization initially. |
| Network dimensions | Hidden dimension **128**, output **64**, cross-network layers **2**. [Training model](/workspace/data/research/gyml/online/train_gyml_online.ipynb:828) | Preserve for baseline; output must match upstream embeddings and API expectations. |
| Serving game selection | Service randomly selects **one** supplied game. [Service transformer](/workspace/data/gyml_online/app/inference/main.py:97) | Preserve stochastic inference or define another selection rule? |
| Serving noise | Adds Gaussian noise with scale **0.24** after model prediction. Notebook evaluation uses the network output without this wrapper. [Service wrapper](/workspace/data/gyml_online/app/inference/main.py:220) | Preserve the noise, and whether evaluation should also measure the served behavior. |

**6. Training, evaluation, and checkpoint selection**

| Parameter or decision | Current value/behavior | Reference |
|---|---|---|
| Epoch count | **5** | [Training settings](/workspace/data/research/gyml/online/train_gyml_online.ipynb:41) |
| Training batch size | **64** | [Training loop](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1063) |
| Incomplete final batch | Dropped by the batch generator | [Batch generator](/workspace/data/research/gyml/online/train_gyml_online.ipynb:714) |
| Optimizer | Adam, learning rate **0.0002**, weight decay **0** | [Optimizer](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1053) |
| Loss | Negative mean diagonal of `log_softmax(predictions @ targets.T)`; other targets in the batch supply competing scores | [Training loop](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1063) |
| Device | No explicit device transfer; tensors/model are created on the default device | [Model creation and training](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1043) |
| Validation/checkpoint interval | Every **2,000** steps; final validation and checkpoint also saved | [Settings](/workspace/data/research/gyml/online/train_gyml_online.ipynb:41), [loop](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1063) |
| Training logging | Every **500** steps, plus every ten steps below step 100 | [Training loop](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1063) |
| Evaluation batch size | **64** | [Metrics](/workspace/data/research/gyml/online/train_gyml_online.ipynb:929) |
| Evaluation metrics | Recall at **10, 30, 100**, using dot-product scores | [Metrics](/workspace/data/research/gyml/online/train_gyml_online.ipynb:929) |
| Candidate population | Unique receivers from the corresponding validation/test split | [Candidate construction](/workspace/data/research/gyml/online/train_gyml_online.ipynb:957) |
| Rank ties | Count candidates with score **greater than or equal to** the target score | [Metrics](/workspace/data/research/gyml/online/train_gyml_online.ipynb:929) |
| Checkpoint selection | Several checkpoints are evaluated manually; export currently uses `STEP = "final"` | [Evaluation examples](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1189), [export selection](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1572) |

We need to choose whether to preserve these settings, how to select a checkpoint automatically, and what validation result permits publication. **There is no acceptance threshold defined in the notebook.**

**7. Execution and output handling**

| Item | Current behavior/reference | Decision |
|---|---|---|
| Development environment | Already settled: use the `ml` environment and code. [Our directory README](/workspace/data/ml/gyml_online/README.md:1), [dependencies](/workspace/data/ml/pyproject.toml:1) | No separate development environment needed. |
| Spark execution | Preparation assumes an existing `spark` session; no standalone launcher/resource configuration. [Notebook start](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:4) | Local Spark for reproduction, remote execution, or both; appropriate resources. |
| Preparation file counts | Writes use `repartition(20)`, `repartition(10)`, and later `coalesce(1)`. [First output](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:316), [pairs](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:417), [final output](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:969) | Preserve initially or adjust after measuring data size. |
| Local data processing | Training reads and joins datasets with pandas, retaining them in memory. [Data loading](/workspace/data/research/gyml/online/train_gyml_online.ipynb:164) | Required memory and where training should run. |
| Existing output directories | Spark writes do not specify overwrite; training explicitly deletes its checkpoint directory before training. [Preparation output](/workspace/data/research/gyml/online/prepare_dataset_for_gyml_online.ipynb:969), [checkpoint cleanup](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1009) | Fail, resume, or overwrite on reruns; identify which artifacts can be reused. |
| Export format | Intermediate checkpoints serialize the model object; final artifact contains `model` and `input_transformer.games_dict`. [Checkpoint save](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1063), [final export](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1572) | Artifact contract and metadata needed to load it reliably. |
| Publication behavior | AWS CLI copies to a fixed model key; failures are caught and printed. [Publication](/workspace/data/research/gyml/online/train_gyml_online.ipynb:1607) | Fail on upload errors; whether existing versions may be replaced. |
| Run metadata | No complete manifest connects inputs, code, settings, metrics, and exported state. | Decide what to record for reproduction and deployment compatibility. |

**8. Service build, deployment, and orchestration**

These decisions can wait until we reproduce training, but they belong in the overall inventory.

| Parameter or decision | Existing definition/use |
|---|---|
| Model state selected for service build | `components.model_version`, currently `MLDE-479-nbclean`. [Version file](/workspace/data/gyml_online/versions.yaml:5), [S3 download](/workspace/data/gyml_online/.ci/build_service_image.sh:43) |
| Service/image versions | `gyml_online_version` and `components.image_service_version`, currently `0.1.13`. Development image tags append `-dev`. [Versions](/workspace/data/gyml_online/versions.yaml:1), [build script](/workspace/data/gyml_online/.ci/build_service_image.sh:12) |
| Base runtime image | `components.image_base_version = 0.1.0`; Docker/Conda with Python 3.9, Torch 2.3.0, NumPy 1.26.4, plus web dependencies. [Version](/workspace/data/gyml_online/versions.yaml:7), [environment](/workspace/data/gyml_online/base/environment.yml:1), [Dockerfile](/workspace/data/gyml_online/base/Dockerfile.gyml_online_base:1) |
| Target service | `service_name = gyml-online-treatment-service`. [Definition](/workspace/data/gyml_online/versions.yaml:1) |
| Deployment environment | `BUILD_ENV_NAME`: `develop` or `prod`; selects image suffix, credentials, ECS cluster, and infrastructure templates. [CI](/workspace/data/gyml_online/.gitlab-ci.yml:14), [deployment script](/workspace/data/gyml_online/.ci/update_ecs_service.sh:12) |
| AWS destination | Region `us-east-1`, ECR repository `gyml-online-service`; ECS clusters `gameram-fargate-develop` and `gapp-prod`. [Deployment script](/workspace/data/gyml_online/.ci/update_ecs_service.sh:13) |
| ECS resources and rollout configuration | Defined separately for development and production in [task definitions](/workspace/data/gyml_online/.aws/task-definition-prod.json:1) and [service definitions](/workspace/data/gyml_online/.aws/service-definition-prod.json:1). Existing infrastructure settings can remain unchanged initially. |
| API contract | Input feature names/platform conversion, nonempty game list, 64-dimensional output. [Request schema](/workspace/data/gyml_online/app/service/main.py:101), [adapter](/workspace/data/gyml_online/app/service/main.py:134) |
| Current deployment trigger | Repository changes activate service CI; production deployment is automatic in production pipelines, development deployment manual. [Root pipeline](/workspace/data/.gitlab-ci.yml:79), [service deployment rules](/workspace/data/gyml_online/.gitlab-ci.yml:53) |
| Future orchestration | Decide when online preparation/training starts, whether every successful GYML training run requires it, and whether service deployment waits for manual acceptance or a validation gate. No connection currently implements that sequence. |

For our **first reproduction**, the essential decisions are much smaller than this inventory:

1. Upstream GYML run and exact historical embeddings.
2. Existing prepared dataset versus rebuilding it, with dates and snapshot cutoff.
3. Online run identity and artifact directories.
4. Which known training/serving differences to preserve or correct.
5. Training settings, checkpoint selection, and success criteria.
6. Execution resources and rerun policy.

The remaining automation and deployment choices can follow once that baseline works. No files changed.


Q:

› Wow! This is a lot! OK, to keep track on things, assign unique id for each item in this list, like '8.1' for 'Service build, deployment, and orchestartion / Model state selected for service build'. And write this list to the file 'MLDE-654-gyml-online-auto.md' under 'decisions' section. OK?


A:

• I’ll add a `decisions` section with stable IDs such as `8.1`, preserving the values, open questions, and source references from the list.

• Added the `decisions` section to [MLDE-654-gyml-online-auto.md](/workspace/data/MLDE-654-gyml-online-auto.md#decisions): **73 uniquely numbered items across eight groups**, with current behavior, decisions to record, and source references.

All IDs and file references were validated.


Q:

› Thanks, approved and commited.


A:

• Thanks. We can now work through the decisions one at a time using their IDs.


Q:

› OK, item 1.1 'Upstream GYML model/index'. We will be using value 'MLDE-479-nbclean' as a reference to upstream GYML model and data. OK?


A:

• I’ll record `MLDE-479-nbclean` as the agreed upstream GYML model and data reference for item 1.1.

• Agreed and recorded in **1.1**: use `MLDE-479-nbclean` as the upstream GYML model and data reference. Exact embedding paths remain under **1.2**.


Q:

› Item '1.2 | Historical embeddings location'. We will be using value 's3://gameram-data/gyml/gnn/train/MLDE-479-nbclean/embeddings/user/' as a remote directory containing parquet files. And, using GYML config and conventions, we should download datasets from remote location to local directory only if local dir is empty. OK?


A:

• I’ll record the S3 path and the agreed download rule, and check the GYML config and code for the matching local-cache convention.

• Agreed and recorded in **1.2**:

- Remote Parquet directory: `s3://gameram-data/gyml/gnn/train/MLDE-479-nbclean/embeddings/user/`
- Download when the local directory is absent or empty.
- Otherwise reuse local data and skip downloading, following the existing GYML convention.


Q:

› Item '1.3 | Online training dataset location'. We will use directory suffix 'MLDE-479-nbclean', and workdir location prefix should be '/tmp/ml/gyml_online'. We will rebuild prepared dataset, using 'overwrite' option on df.write.


A:

• I’ll record the dataset rebuild and overwrite decision, and update the related working-directory item to `/tmp/ml/gyml_online/MLDE-479-nbclean`.

• Recorded in **1.3**, **1.5**, and **7.5**:

- Workdir: `/tmp/ml/gyml_online/MLDE-479-nbclean`
- Rebuild prepared datasets using `df.write.mode("overwrite")`.
- Downloaded source data still follows the reuse rule from **1.2**.


Q:

› Item '2.1 | Event date range'. In GYML we use 'features_date_range' as 30 days, and `"run_dth":"2026-11-05 06"`. So in gyml-online we should use the same range of data partitions. I don't know why notebook use 6 weeks interval. Any suggestions?


A:

• I’ll check how GYML defines the partition boundaries, then compare that with the notebook’s date-only filtering.

• Agreed—using the same window gives us a consistent baseline with upstream GYML. The notebook doesn’t document why it uses roughly six weeks; I wouldn’t preserve that interval without evidence it is needed.

For `run_dth = "2026-11-05 06"`, use:

```text
2026-10-06 06:2026-11-05 06 UTC
```

Include both boundary hour partitions, following GYML conventions. We must filter by **date and hour**, since the notebook’s date-only filters would include extra hours.

Recorded in **2.1**. Snapshot timing remains separate under **2.2**.


Q:

› Item '2.2 | Snapshot date/hour'. We should preserve this '+1 day' decision for tables snapshots. As I understand it, it gives us a stable user's profile in case the user is new in system. Probably, given 'run_dth' from GYML, we should use '-1 day' cutoff for events 'date_to' and 'run_dth' for snapshots. Am I wrong?


A:

• That is reasonable: use snapshots at `run_dth`, and leave a one-day gap between the last events and the snapshot. This gives recently registered users time to appear in the snapshots and populate their profiles. It improves completeness, but doesn’t guarantee a stable profile.

There are two details to settle:

- **Window length:** this changes **2.1**. To retain a 30-day window, shift both event boundaries:
  ```text
  Events:    2026-10-05 06 → 2026-11-04 06 UTC
  Snapshots: 2026-11-05 06 UTC
  ```
  Keeping the previously agreed start, October 6 at 06:00, would shorten the window to 29 days.

- **Hours versus calendar days:** the notebook uses events through a whole calendar day, then snapshots at midnight the next day. Your proposed hourly equivalent leaves a full 24-hour gap. If you mean “all events through November 4,” the final event partition would instead be `2026-11-04 23`.

My suggestion is to use the **30-day hourly window shifted back one day**, with snapshots at `run_dth`. It gives us explicit, reproducible boundaries. Also, these are snapshots *as of the cutoff* applied to historical examples, rather than profiles as they existed at each event.

I haven’t changed **2.1–2.2** yet, since this revises the previous decision.


Q:

› I agree with your suggestion, do it.


A:

• I’ll update **2.1–2.2** to use a 30-day hourly event window ending one day before `run_dth`, with table snapshots at `run_dth`.

• Updated **2.1–2.2** in [the task document](/workspace/data/MLDE-654-gyml-online-auto.md#decisions):

- Events: `2026-10-05 06` through `2026-11-04 06` UTC, inclusive hourly partitions.
- Table snapshots: `2026-11-05 06` UTC.

The window remains 30 days, ending one day before `run_dth`.


Q:

› Item '1.4 | Online model version'. This value (directory suffix) should contain two parts: upstream index_id (as gyml model id), and gyml-online versioned suffix. I suggest this value 'MLDE-479-nbclean-261111'.


A:

• I’ll record `MLDE-479-nbclean-261111` as the online model version, with the upstream GYML ID and online version suffix identified separately.

• Recorded in **1.4**:

- Format: `<upstream_index_id>-<online_version_suffix>`
- This version: `MLDE-479-nbclean-261111`
- Model artifact: `s3://gameram-data/gyml/gyml-online/MLDE-479-nbclean-261111/cold_model_state.pth`

The workdir remains `/tmp/ml/gyml_online/MLDE-479-nbclean`, as agreed in **1.5**.


Q:

› Item '1.6 | Intermediate names'. It seems like 'dataset_name' is used as versioning path suffix. In that case it should be like 'ds_261111'. Then `model_save_dir = f"{project_prefix}/models/{dataset_name}"`,
`final_state_dir = f"{project_prefix}/final_states/{dataset_name}"`. And `datasets_raw_dirname = "datasets_raw"`. Should be enough?


A:

• Yes, that’s enough for those paths:

```python
dataset_name = "ds_261111"
datasets_raw_dirname = "datasets_raw"

model_save_dir = f"{project_prefix}/models/{dataset_name}"
final_state_dir = f"{project_prefix}/final_states/{dataset_name}"
```

One remaining detail: the vocabulary dictionaries should also live under a dataset-specific directory, such as:

```python
artifacts_dir = f"{project_prefix}/artifacts/{dataset_name}"
```

That keeps a rebuilt vocabulary from overwriting dictionaries belonging to another dataset version. We still need to choose the dictionary filenames.


Q:

› Yes, agree about artifacts.


A:

• I’ll record the agreed names in **1.6**, including the dataset-specific artifacts directory. Dictionary filenames will remain pending.

• Recorded in **1.6**, including `artifacts/{dataset_name}` for vocabulary dictionaries. Only dictionary filenames remain pending for this item.


Q:

› > Only dictionary filenames remain pending for this item. You mean 'gg4', 'ggi4', 'gga4'?


A:

• Yes—those three:

- `gg4`: requested-game vocabulary (`games_dict_path`).
- `ggi4`: intersected-game vocabulary (`games_intersected_dict_path`).
- `gga4`: profile-added-game vocabulary (`games_added_dict_path`).

They can retain these names or get descriptive filenames such as `games.json`, `games_intersected.json`, and `games_added.json`.


Q:

› Lets use descriptive filenames, good idea.


A:

• I’ll record the descriptive dictionary filenames in **1.6**.

• Recorded in **1.6**: `games.json`, `games_intersected.json`, and `games_added.json`, all under `artifacts/ds_261111/`.


Q:

› Item '3.1 | Account features'. Check please, in GYML data collection, what sources do we use? gyml-online should use the same features data as GYML.


A:

• I’ll trace GYML’s user-feature collection from its active config to the source readers, then compare it with the online model’s required features.

• Yes. GYML’s user-feature collection primarily uses **S3 dumps**, with a separate ClickHouse source for legacy locale fields.

The source list is in [GNNUserFeaturesJob.load_user_sources](/workspace/data/ml/data/pyspark_job/nodes.py:512):

| Source | Used for |
|---|---|
| S3 `postgres-dump/account` | Birth date, gender, profile text/link/name/avatar, country, account status and activity |
| S3 `postgres-dump/account_languages` | `language`, currently selected with `any_value(code)` |
| S3 `external/regions` | `region_new`, derived from the account’s country |
| S3 `postgres-dump/account_platforms` | Platform flags |
| S3 `postgres-dump/account_games` | Added-game counts; online preparation also needs actual game lists |
| ClickHouse `analytics.user_profile_snapshot` | Legacy `locale` projection, producing the older language/country fields |
| S3 `parquet/subscription-event` | Skip/not-interested activity features |
| Other S3 dumps | `playerid`, `post_likes`, `account_status`, `account_subscriptions`, `account_explore_goals` for additional GYML features |

Two distinctions matter:

- The [GYML graph config](/workspace/data/ml/configs/graph/graph.yaml) uses **`indexed_language` and `indexed_region_new`**. Those originate from account-language rows and the account’s country—not the legacy profile-derived pair.
- Sharing sources doesn’t require adding every GYML feature to the online model. Online preparation additionally needs registration date, game lists, and recommendation context. GYML’s raw account projection doesn’t retain all of those.

We should reuse applicable readers and preparation helpers, while keeping the separate event and snapshot cutoffs agreed in **2.1–2.2**.

Recorded this decision and the source breakdown under **3.1** in the task document. No notebook or implementation changes.


Q:

› Actually, to reproduce the current gyml-online pipeline, we shouldn't change features preparation (or other logic). But we can (and should) take a note about differences, for addressing it later, during fixing and refactoring phase.


A:

• Understood. I’ll correct **3.1** to preserve the notebook’s feature preparation for reproduction and mark the GYML differences as notes for the later fixing/refactoring phase.

• Agreed. Updated **3.1** and added a general reproduction principle:

- Preserve notebook logic, except for explicitly agreed parameter/path changes.
- Record differences and suspected defects for later fixing/refactoring.
- Keep the GYML comparison as reference, without importing its filters or dependencies.

Only the task document changed.


Q:

› Perfect!


A:

• We’ll use that as the rule for the reproduction phase.


Q:

› Item '3.2 | Age reference date'. As agreed, we leave current implementation and make a note for future fix.


A:

• I’ll mark **3.2** as agreed: keep Spark `current_date()` for reproduction and note the reference-date change for later.

• Recorded in **3.2**: preserve `current_date()` for reproduction; note an explicit age reference date as a future fix.


Q:

› Item '3.3 | Language'. The same


A:

• I’ll record **3.3** the same way: preserve the notebook’s language selection for reproduction and note primary-language selection for later.

• Recorded in **3.3**: preserve `any_value(code, ignoreNulls=True)` for reproduction; primary-language selection and alignment with serving are noted for a future fix.


Q:

› Show me items from our list, that require similar decisions, in abbreviated form, one item on one line


A:

• Remaining candidates for **“preserve for reproduction; review/fix later”**:

- **2.5 — Duplicate examples:** arbitrary event retained per user pair.
- **2.6 — Recommendation context:** joins subscriptions without temporal matching.
- **2.7 — Corrupt files:** silently skips corrupt subscription files.
- **3.4 — Region:** external mapping and inner join instead of profile region.
- **3.6 — Profile games:** arbitrary selection of up to 32 games.
- **3.8 — Missing features:** preserve existing joins, exclusions, and defaults.
- **4.2 — Split ordering:** no tie-breaker within the same date/hour.
- **4.3 — Split sizes:** fixed counts; no explicit handling of insufficient data.
- **4.6 — Vocabulary construction:** preserve category assignment and reserved IDs.
- **4.7 — Game sampling:** random selection of up to three games.
- **4.8 — Empty/null games:** empty lists produce no samples; null produces an unknown-game sample.
- **4.9 — Random seeds:** Torch seeded; Python sampling unseeded.
- **4.10 — Inactive game mode:** vocabulary mismatch in the unused branch.
- **5.3 — Gender encoding:** separate training and serving implementations.
- **5.5 — Locale encoding:** reversed dictionary in serving.
- **5.7 — Vocabulary size:** derived in training, hardcoded in serving.
- **5.9 — Serving game selection:** randomly selects one game.
- **5.10 — Serving noise:** adds noise absent from training evaluation.
- **6.3 — Final batch:** incomplete batches are dropped.
- **6.11 — Evaluation candidates:** drawn only from the corresponding split.
- **6.12 — Rank ties:** equal scores count against the target.
- **6.13 — Checkpoint selection:** manual comparison; final checkpoint exported.
- **7.3 — Output partitions:** fixed repartition/coalesce counts.
- **7.6 — Checkpoint format:** intermediate checkpoints serialize the model object.
- **7.7 — Publication errors:** upload failures are caught and printed.

These include possible improvements as well as defects; preserving them now doesn’t imply every item needs changing later.


Q:

› And this list contains no stoppers for pipeline reproduction?


A:

• Most items won’t block reproduction, but **three require checks before we can say that confidently**:

- **5.7 — Game vocabulary size:** a newly trained state won’t load in the service if its game embedding size differs from the hardcoded `228`. Matching that size is an integration requirement.
- **4.3 / 4.8 — Usable data volume:** fixed split sizes and empty-game filtering could leave training or evaluation without enough samples.
- **7.6 — Serialized checkpoints:** extracting notebook code into scripts can change Python class/module identities, so checkpoint saving and reloading must be tested.

**4.10** does not block the active `flag_games_intersected=True` path. The locale mapping issue (**5.5**) affects prediction correctness but ordinarily doesn’t prevent execution.

So the list contains mostly deferred improvements, plus **conditional blockers**. We haven’t run the pipeline yet; preserving existing logic gives us a baseline, not proof that it will execute successfully. If a blocker appears, we’ll isolate it and agree on the minimum change needed.


Q:

› OK, I see no actual stoppers. So, it is safe (for now) to apply our rule for this list. Rule: preserve current implementation and make a note for later fix/refactoring, remember?


A:

• Yes. I’ll mark all 25 items as “preserve for reproduction,” with the concerns retained as notes for later fixing or refactoring.

• Applied the rule to all **25 items** in the task document: preserve current implementation for reproduction, with concerns recorded for later fixing/refactoring.

No implementation or notebook files changed.


Q:

› OK, good. Update doc section 'First reproduction: decision order', please. What decisions still pending?


A:

• I’ll check the remaining decision statuses and update “First reproduction: decision order” to distinguish pending reproduction choices from later deployment work.

• Updated **“First reproduction: decision order.”**

Remaining reproduction decisions:

- **7.2:** Where Spark preparation runs and its memory/CPU allocation.
- **6.6 + 7.4:** Training host/resources and CPU versus GPU.
- **7.5:** Checkpoint cleanup and reuse of training artifacts.
- **7.8:** Minimal run metadata now, or defer a manifest.

Existing notebook settings follow our preservation rule. Data availability and compatibility checks are verification work.

**6.14** publication acceptance and **8.1–8.10** deployment/automation decisions remain for the next phase.


Q:

› Item '7.2 | Spark execution'. For pipeline reproduction we will be using local box and local spark session. Two cores and 16GB RAM should be enough.


A:

• I’ll record local Spark with two cores and 16 GB RAM for **7.2**, and mark that execution choice as settled.

• Recorded **7.2**: local Spark session, `local[2]`, and 16 GB driver memory. Updated the decision-order section to mark it settled.


Q:

› Item '6.6 | Device'. I have no GPU on local box, so - CPU.


A:

• I’ll record CPU for **6.6**.

• Recorded **6.6**: CPU for reproduction. The decision-order section is updated accordingly.


Q:

› Item '7.4 | Local data processing'. Local box, 16GB RAM.


A:

• I’ll record the local machine with 16 GB RAM for **7.4** and mark the training-host decision as settled.

• Recorded **7.4**: local machine, 16 GB RAM, CPU, preserving pandas in-memory processing.

Only **7.5** (rerun policy) and **7.8** (run metadata) remain pending for reproduction.


Q:

› Item '7.5 | Existing output directories'. Basic policy is 'overwrite'.


A:

• I’ll record overwrite as the default for generated outputs, while preserving the agreed reuse of nonempty downloaded-source directories.

• Recorded **7.5**: overwrite generated outputs, including checkpoint cleanup before training. Nonempty downloaded-source directories remain reusable under **1.2**.

Only **7.8 — Run metadata** remains pending.


Q:

› Item '7.8 | Run metadata'. It's not a show-stopper, isn't it?


A:

• Correct—run metadata is not a blocker for reproduction. We can defer the manifest to the automation/refactoring phase and use the agreed parameters and normal logs for now.


Q:

› OK, make note for this item


A:

• I’ll mark **7.8** as deferred and update the reproduction checklist accordingly.

• Recorded **7.8** as deferred to automation/refactoring. The checklist now shows no remaining reproduction decisions; implementation and verification are next.


Q:

› Perfect! Let me verify our work one more time


A:

• Take your time. I’ll wait for your review before proceeding.


Q:

› OK, verified and commited, thanks. Now we are ready to start reproducing the current gyml-online pipeline. Last step before we begin: I need an overview of that pipeline to be documented. Lets create a section in our document, name 'gyml-online notebook pipeline'. There should be identified elements of data flow and data transformations, with short descriptions. Any not-obvious operations or options should be highlighted. CAn we do that?


A:

• I’ll add a “gyml-online notebook pipeline” section tracing the inputs, intermediate datasets, transformations, training, and export. I’ll highlight operations that affect the results, especially sampling, joins, filtering, and notebook-specific behavior.

• The key distinction is that each example uses the requesting user’s features and game context to predict the recommended user’s GYML embedding. The flow also has two non-obvious steps worth documenting explicitly: `games` is a nested array, and the final game intersection is with the receiver’s profile games.

• Added [gyml-online notebook pipeline](/workspace/data/MLDE-654-gyml-online-auto.md#gyml-online-notebook-pipeline), covering:

- Data-flow diagram and intermediate datasets.
- Feature transformations, joins, filtering, sampling, training, and export.
- Non-obvious behavior and agreed reproduction adaptations.
- Notebook source references and the boundary with serving.

References validated; notebooks unchanged.


Q:

› OK, it is a good start. Can you identify used datasets and their transformations? As I understand, there is tables (snapshots) and events, each have name.


A:

• I’ll reorganize the input inventory by dataset name, separating snapshots from event histories and describing what each contributes and how it is transformed.

• Yes—there are **eight external datasets**:

| Kind | Name | Main transformation |
|---|---|---|
| Snapshot | `account` | Derive requester features; retain registration date |
| Snapshot | `account_languages` | Select one non-null language per account |
| Snapshot | `account_platforms` | Pivot platform codes into presence flags |
| Snapshot | `account_games` | Collect requester games; separately intersect requested games with receiver games |
| Lookup | `regions` | Map account country to region |
| Events | `subscription-event` | Select registration-day requester/receiver pairs |
| Events | `gyml-sent-event` | Extract recommended receivers and request-game context |
| Model output | Historical user embeddings | Join receiver ID to its target vector |

Added these to **“Named input datasets and their transformations”** in the document, with locations, consumed columns, joins, outputs, and source references.

Also clarified that the cutoff `gyml-sent-event` partition supplies a **schema**, not a table snapshot.


Q:

› Very good! Can we add information about read/write actions to diagram?


A:

• I’ll add read/write labels and persisted dataset names to the diagram, keeping it aligned with the notebook stages.

• Updated the diagram with explicit reads, writes, and transfers: Parquet stages, JSON dictionaries, model checkpoints, and S3 publication.

Added a legend and clarified how the notebook’s S3 intermediates map to our agreed local reproduction workflow.


Q:

› Wonderful, all documented. OK, now we should reproduce data collection and preparation stage (spark). Should it be one python module?


A:

• Yes—one module, `ml/gyml_online/prepare_dataset.py`, should be enough initially.

Use small functions matching the documented stages:

- Read snapshots and prepare requester features.
- Read and filter subscription events.
- Read recommendation events and aggregate game context.
- Join pairs and compute receiver-game intersections.
- Write intermediate and final datasets.

Keep Spark creation, configuration, and execution in `main()`, so the transformation functions can accept a Spark session or DataFrames and be exercised independently.

Preserve the notebook’s intermediate read/write boundaries and logic. We can split the module later if its size or reuse warrants it.


Q:

› Keep in mind: here and now we just reproducing the pipeline. Fixes, refactoring, re-design - all that we will do later.


A:

• Understood. One module that follows the notebook’s execution order and preserves its logic and intermediate read/write stages. Only the explicitly agreed parameters, paths, and execution settings change. Fixes and restructuring come later.


Q:

› Yes, lets begin


A:

• I’ll create the Spark preparation module in `ml/gyml_online/`, following the notebook cell order and preserving its intermediate read/write stages. I’ll apply only the agreed paths, dates, Spark settings, and overwrite policy.

• The local ML environment is ready, but there are no AWS credentials or cached inputs in this session, so I can’t run against the real S3 data yet. I’ll keep the module’s transformations in notebook order, add the local download step, and verify the Spark flow with small local Parquet fixtures.

• The module passes the local Parquet smoke test, including a full rerun over existing outputs. The test checks hourly boundaries, registration-day filtering, nested request games, receiver-game intersections, and preservation of pairs with no intersection. The README now includes the run command and output path; the real-data run remains blocked by missing AWS credentials.

• Created [prepare_dataset.py](/workspace/data/ml/gyml_online/prepare_dataset.py), preserving notebook order and intermediate I/O, with the agreed parameters and local caching.

Updated the README. The local Parquet smoke test—including overwrite rerun—passed; formatting and syntax checks passed.

Real S3 execution is pending: this session has no AWS credentials or cached inputs. Notebooks remain unchanged.


Q:

› Cool! OK, we made some progress, update the doc, please


A:

• I’ll update the task document with what’s implemented, what passed locally, and what remains before the real-data run.

• Updated [MLDE-654-gyml-online-auto.md](/workspace/data/MLDE-654-gyml-online-auto.md#reproduction-progress) with implementation status, successful local checks, the AWS-access prerequisite, and next steps for real-data preparation and training extraction.


Q:

› OK, now model training code. Also one module, I presume?


A:

• Yes—`ml/gyml_online/train.py`, following the training notebook’s order: load prepared data and upstream embeddings, split, build vocabularies, transform/sample, train, evaluate, and export.

Preserve existing logic and intermediate files; apply only our agreed parameters, paths, CPU settings, and overwrite policy. No fixes or redesign yet.


Q:

› Lets go


A:

• I’ll create `ml/gyml_online/train.py` from the training notebook, preserving its sequence and logic while applying the agreed paths, CPU execution, caching, and overwrite policy.

• The module will keep the notebook’s split sizes, vocabularies, model, loss, sampling, and checkpoint format. I’ll use the local prepared dataset and cache the upstream embeddings as agreed. The final checkpoint remains the default export; the notebook’s alternative checkpoint comparisons will stay optional.

• The training smoke test passed: it used cached Parquet inputs, kept the original split sizes, trained on CPU, saved and reloaded periodic/final checkpoints, and exported the state. S3 publication was mocked. I also checked that all 13 model, transformation, batching, vocabulary, and metric definitions match the notebook’s parsed code exactly.

• Created [train.py](/workspace/data/ml/gyml_online/train.py) with the notebook’s training, evaluation, checkpoint, and export logic. Updated README and task progress.

Both preparation and training smoke tests passed; formatting and syntax checks passed. No notebooks changed.

Real-data execution remains pending: no prepared dataset, AWS credentials, or AWS CLI are available here. The training command attempts S3 publication after export.


Q:

› Wonderful! I commited all changes, but real data processing as E2E tests should wait until tomorrow. Enough for today.


A:

• Agreed. Tomorrow we’ll run preparation and training against real data, then verify outputs and resource usage. No further changes today. See you tomorrow!


Q:

› Export today’s session, please


A:

• I’ll use the export-session-dialog skill to save today’s conversation in the agreed Q/A format, without tool calls or command logs.

## 2026-11-13 gyml-online dev

Q:

› Hi, where were we?


A:

• We’re working on **MLDE-654: automating gyml-online**, currently reproducing the existing notebooks before fixes or refactoring.

Completed and committed:

- Documented the pipeline, datasets, transformations, and decisions in `MLDE-654-gyml-online-auto.md`.
- Created `ml/gyml_online/prepare_dataset.py` and `train.py`, preserving notebook logic with the agreed paths and settings.
- Both local smoke tests passed. READMEs and progress notes are updated.

**Next:** run preparation and training against real data, then verify schemas, row counts, checkpoints, and resource usage. The last session lacked AWS credentials, AWS CLI, and prepared data.

Our reference is `MLDE-479-nbclean`, workdir `/tmp/ml/gyml_online/MLDE-479-nbclean`, using local Spark and CPU. Training currently attempts S3 publication after export, so that step needs attention before the real run.


Q:

› Ah, OK, got it. Lets continue. I have done checking, running and validating our two scripts. They works as they should, we did good job. I've updated a little documentation and scripts code, take a look


A:

• I’ll read your updates and compare them with the previous versions to understand the current scripts and documentation. I’ll take your real-data validation as confirmed and keep deferred fixes outside this pass.

• I’ve read the updates. The reproduction phase is complete, based on your real-data validation; we’re now at pipeline design.

The changes capture:

- Shared version naming via `ONLINE_INDEX_VERSION`.
- Preparation constants for the date range, platforms, and game limit.
- Actual dataset sizes, schema, samples, feature distributions, and vocabulary sizes.
- Evaluation of `"final"` and `"14000"` checkpoints; export still selects `"final"`.
- TODOs for PySpark-job integration, configuration, paths, and checkpoint selection.

Three documentation details remain stale:

- The task document still says real-data execution is pending.
- README says checkpoint comparisons are empty by default.
- The service README link should use `../../gyml_online/README.md`.

The recorded game vocabulary size is **159**, while serving still hardcodes **228**—the known integration point to address in the next phase.

No files changed or real-data runs repeated.


Q:

› OK. Stale documentation details we will update after this: move our two scripts to 'ml/gyml_online/notebook_migration/' and make a note that it is a result of the first stage of migration from manual pipeline to auto. We will use those scripts as a source of logic (code) for production-ready modules, but should not edit them.


A:

• I’ll move both scripts into `notebook_migration/`, update their tests and documentation references, and document them as frozen stage-one outputs to use as references for production modules.

• Moved both scripts to [notebook_migration/](/workspace/data/ml/gyml_online/notebook_migration/) with their contents unchanged.

Documented them as frozen stage-one references, added scoped `AGENTS.md` guidance, and updated imports and commands. Both smoke tests passed.

The broader stale-documentation cleanup remains for the next step.


Q:

› move their tests also, please


A:

• I’ll move the tests alongside the frozen scripts and update their documented paths.

• Moved both tests to `ml/gyml_online/notebook_migration/tests/` and updated documentation paths. Both tests passed from their new location.


Q:

› OK, commited. Now we can fix stale docs


A:

• I’ll update the stale status, checkpoint-comparison description, and service README link to reflect the validated migration and frozen reference layout.

• The docs now mark real-data reproduction as complete and production-pipeline design as the current phase. They also reflect comparison of `"final"` and `"14000"` checkpoints while export still selects `"final"`. Service compatibility and deployment remain separate checks; the frozen scripts are untouched.

• Updated the task document and README:

- Marked real-data reproduction complete; production design is next.
- Removed stale execution blockers.
- Corrected checkpoint-comparison details and the service README link.
- Preserved all 73 decision IDs.

Links validated. Frozen scripts and tests unchanged.


Q:

› OK, now - the interesting part: design of a new system. First we should discuss an overwiew of a system, reveal non-obvious hurdles, and solve them. Ater we agree on details, we should create a design-doc where we describe our solution and decisions. And after that we could implement the design. As simple as that. OK?


A:

• Agreed. We’ll discuss the system overview, identify the non-obvious hurdles, and work through the decisions first. Once the design is agreed, we’ll write the design document, then implement it component by component.

The validated migration scripts remain frozen references throughout.


Q:

› OK. As I see it, the automated gyml-online pipeline will be orchestarated by some Airflow DAG, similar to dag 'gyml_gnn_train'. The new DAG name will be 'gyml_online_train'. DAG parameters 'run_dth' and the list of stages to run, like in gyml_gnn_train. Stages: 'data_collect', 'train', 'deploy'.


A:

• Agreed. The orchestration outline is:

- **DAG:** `gyml_online_train`
- **Parameters:** `run_dth` and `stages`
- **Stages:** `data_collect` → `train` → `deploy`

We can follow `gyml_gnn_train` for selecting stages and passing the reference date/hour.

One important contract to settle next: **when earlier stages are skipped, how does a selected stage identify the existing artifacts it should consume?** For example, running only `deploy` must identify a particular trained online-model version.

That connects to where we define the upstream GYML `index_id` and the online version suffix. We should settle those identities before detailing the stages.


Q:

› We have more than one connection to external systems and artifacts. They will be revealed as we discuss pipeline stage-by-stage.


A:

• Understood. We’ll work through `data_collect`, `train`, and `deploy` in order, identifying each stage’s inputs, outputs, external connections, and behavior when other stages are skipped.


Q:

› OK, data_collect stage. It is our 'prepare_dataset' script, but implemented as AWS EMR step (spark-submit job), similar to 'batch.gyml.train_tasks.data_collect.DataCollectTasks.get_collect_nodes_tg', for example. Lets say in file 'ml/data/pyspark_job/gyml_online.py'. It needs features-date-range as a parameter, which require 'run_dth' as a base and number of days as a range size. Also it needs 'index_id' and 'index_id_online' as S3 path variables, so it could write result to path like 's3://gameram-data/gyml/gyml-online/data/MLDE-479-nbclean-261111/dt=2026-11-13/hour=14/'. Here 'MLDE-479-nbclean' is index_id, and '261111' is index_id_online - gyml-online model version under upstream 'MLDE-479-nbclean' effectively.


A:

• I’ll check the existing EMR-step and PySpark job conventions so we can discuss the stage’s interface and S3 outputs concretely. I won’t change code yet.

• Agreed. `data_collect` becomes an EMR Spark step, implemented in `ml/data/pyspark_job/gyml_online.py` and launched through the existing PySpark runner conventions.

Its inputs are:

| Parameter | Role |
|---|---|
| `run_dth` | Snapshot cutoff and output partition date/hour |
| Features range size | Number of event-history days, initially 30 |
| `index_id` | Upstream GYML model ID: `MLDE-479-nbclean` |
| `index_id_online` | Online version within that upstream model: `261111` |

Keeping our agreed one-day offset, Airflow derives the inclusive event range:

```text
date_to   = run_dth - 1 day
date_from = date_to - range_size
```

It can pass that range, `run_dth`, and both IDs to the Spark job. Spark reads sources directly from S3; the local download/cache step belongs only to the frozen reproduction scripts.

For `run_dth = "2026-11-13 14"`, the final prepared dataset goes to:

```text
s3://gameram-data/gyml/gyml-online/data/MLDE-479-nbclean-261111/dt=2026-11-13/hour=14/
```

One output-layout detail matters: **intermediate checkpoints must live outside that final dataset directory**, so training cannot accidentally read intermediate Parquet files as examples. We should settle their location and whether production preparation retains all existing checkpoint boundaries next.

No code or design-document changes yet.


Q:

› Something like that, we will discuss details later. For now just take a note that they should be discussed, the job contract should be defined as exact as possible.


A:

• I’ll add a discussion note to the task document, marking the `data_collect` outline as provisional and listing the contract details we still need to define.

• Noted in the task document: the `data_collect` outline is provisional. Its exact arguments, time boundaries, sources, output schema/paths, checkpoints, and rerun/failure behavior must be discussed and defined before implementation.


Q:

› OK, train stage. It is, basically, our train script, executed similar to 'batch.gyml.train_tasks.train.get_train_tg'. As parameters it needs 'index_id' and 'index_id_online', to find input data on S3 and write output on S3.


A:

• I’ll record the `train` outline using `get_train_tg` as the execution reference, with the exact input and output contract still to be defined.

• Recorded the `train` outline: execute the training logic using the existing remote-training pattern, with `index_id` and `index_id_online` identifying S3 inputs and outputs.

Also noted that selecting the dated input partition must be defined in the exact contract.


Q:

› sure, 'run_dth' also should be passed as parameter to help with path resolving


A:

• I’ll add `run_dth` to the training parameters for path resolution.

• Recorded: training receives `index_id`, `index_id_online`, and `run_dth` for S3 path resolution.


Q:

› OK, 'deploy' stage. It will be not trivial. The idea is similar to airflow dag 'feed_als_ml_train', where we use 'batch.feed.als_train.get_gitlab_tg' to start gitlab ci/cd pipeline. We should make changes in project 'gyml_online/' so we could trigger its ci/cd pipeline. And that ci/cd will be building docker image and create/update AWS ECS service. As of now I can see this important parameters: deploy env selector - prod or develop; split name to define endpoint name (control or treatment), index_id and online_index_id to help with path resolving.


A:

• I’ll check the ALS GitLab-trigger pattern and the current gyml-online CI/CD inputs, then record this deploy-stage outline and the contract details still to discuss.

• Recorded the provisional `deploy` outline: Airflow triggers and monitors GitLab CI/CD, which builds/tests the image and creates or updates ECS.

Initial inputs are environment, split, upstream ID, and online model version. Environment and split remain separate selectors.

Noted for later discussion: exact variable names, artifact paths, image versioning, Git ref, and deployment-success criteria—including standardizing `index_id_online` versus `online_index_id`.


Q:

› OK, now we should settle where parameters should be defined: I can see at least 3 category of parameters, based on the place of definition: dag-run parameter with value defined in web-ui form in the moment of manual start of the dag; pipeline parameter with value defined as global python variable in dag module; config parameter with value defined in some yaml config, usually for a particular job.


A:

• Yes—those three categories give us a clear ownership model:

| Category | Defined in | Purpose | Examples |
|---|---|---|---|
| **DAG-run parameters** | Manual-start form | Values chosen for a particular execution | `run_dth`, `stages` |
| **Pipeline parameters** | DAG-module globals | Configure the pipeline and coordinate stages | Model IDs, deployment environment/split, package versions, EMR/EC2 resources, Git ref |
| **Job configuration parameters** | Job YAML | Control a job’s data processing or model behavior | Cold-user threshold, game limit, vocabulary threshold, batch size, epochs, optimizer settings |

The examples beyond `run_dth` and `stages` are proposed assignments—we should agree on their placement.

Two principles would help:

- **One authoritative definition per parameter.** Passing a pipeline parameter to a job or GitLab makes it an input there, not another independently configured value.
- **Derive values rather than configure them separately.** Combined model IDs, date ranges, and resolved S3 paths should come from their constituent parameters.

One non-obvious case is **feature-range size**. If Airflow computes the range and uses it for readiness checks, the size belongs at pipeline level. If only the Spark job needs it and computes the range itself, it can belong in that job’s YAML. We should choose the owner alongside the job contract.

Similarly, the job contract should identify which values are supplied by orchestration and which come from YAML, including any permitted overrides.


Q:

› We should create a table that describe all our parameters. For each parameter there should be name, short description explaining meaning of parameter, category, default value if any, data type and format, examples.


A:

• I’ll add a parameter inventory to the task document with those columns. I’ll mark unsettled names, categories, and defaults explicitly so the table doesn’t turn proposals into decisions.

• I’m separating explicit inputs from derived values such as date ranges and S3 paths. The table will also distinguish frozen-script values from proposed production defaults; those aren’t automatically the same.

• Added the [draft parameter inventory](/workspace/data/MLDE-654-gyml-online-auto.md#parameter-inventory-draft) with all six requested columns.

It separates run/pipeline parameters, job/service settings, and derived values. Unsettled categories, names, and defaults are marked explicitly; existing values are shown as reference examples.

No implementation changes.


Q:

› Well, by the way, design notes for automated pipeline should be placed in a ne file, lets name it 'MLDE-654-gyml-online-auto-design.md.


A:

• I’ll move the automated-pipeline discussion notes and parameter inventory into `MLDE-654-gyml-online-auto-design.md`, and link it from the original task document.

• Moved the automated-pipeline notes and parameter inventory to [MLDE-654-gyml-online-auto-design.md](/workspace/data/MLDE-654-gyml-online-auto-design.md).

The original document links to it and retains the investigation, reproduction decisions, and validation history. All entries and source links were preserved.


Q:

› Good. I still have a few notes about my view on 'how it should work' in general. Parameters 'deploy env' and 'split' should be in the category of dag-run. gyml-online train script should be similar to GYML GNN train script it the way how it operates (config, pre/post train, adapters, logs). Probably we should add 'gyml-online' submodule to hydra ml/configs. Path resolving everywhere should be implemented as methods or properties of a class e.g. PathResolver.


A:

• I’ll record these design constraints: deployment environment and split as DAG-run inputs, GYML-style training structure, the proposed Hydra config group, and centralized path resolution.

• Updated the design draft:

- `deploy_env` and `split` are now **DAG-run parameters**.
- Training follows GYML GNN’s config, pre/post-train, adapter, and logging structure.
- A `gyml-online` Hydra group under `ml/configs/` is recorded as a proposal.
- Production paths are resolved through class methods/properties, such as `PathResolver`.

The resolver’s packaging across Airflow, EMR, training, and CI remains a detail to settle.


Q:

› Great! One more, about dependencies. The system engaged three 'data' components: airflow, gyml_online, and ml. Airflow DAG will be using ml package version and gyml_online git tag as dependency, in form of pipeline parameters. And gyml_online will be using ml package version, as ml model inference code should be resided in ml package. In that case ml package version looks like a config parameter and it place is in 'gyml_online/versions.yaml' probably.


A:

• I’ll add that dependency relationship to the design and clarify the two uses of the ML package version: a pipeline input in Airflow and a service dependency in `gyml_online/versions.yaml`. We’ll also need to define which value wins when CI receives an override.

• Yes—the category depends on who defines and consumes the value:

- **Airflow:** ML package version and gyml-online Git tag are pipeline parameters.
- **gyml_online:** its ML inference dependency belongs in service configuration, probably `versions.yaml`.
- **ml:** owns the model inference implementation consumed by the service.

Recorded this in the design draft, with `components.ml_package_version` as a proposed YAML key.

One contract remains open: whether the service tag pins that dependency and Airflow must match it, or CI permits an explicit override. We should avoid silently combining incompatible trained state and inference code.


Q:

› there will be no override in CI, for CI only one ml package version should be visible, from 'versions.yaml'.


A:

• I’ll record `gyml_online/versions.yaml` as CI’s sole source for the ML package version and remove the override option from the design.

• Recorded: service CI reads the ML package version **only from `gyml_online/versions.yaml`**, with no override.

Airflow’s ML package version configures preparation/training; the selected service Git tag pins the inference dependency used for deployment.


Q:

› OK, that should conclude design overwiew. Or am I missing something in the 'big picture'?


A:

• The overall shape is complete: **Airflow → EMR data collection → remote training → GitLab build/deploy → ECS serving**. We don’t appear to need another stage.

Two cross-system responsibilities deserve an explicit place in the overview:

- **Model compatibility:** how we verify that the trained state matches the inference code pinned by the selected service Git tag. This includes the model architecture, feature transformations, and upstream embedding space.
- **Activation coordination:** how the deployed `control`/`treatment` endpoint stays paired with the correct upstream GYML index. Deploying a healthy service alone doesn’t establish that pairing.

We can leave their exact mechanisms for detailed design, alongside checkpoint selection, artifact contracts, retries, and rollout success criteria. They don’t require changing the three-stage outline.


Q:

› For the first question I have a solution, more likely half of it: in CI we should perform smoke-test of a service. I believe current version have one. For the second question I can say only this: cross-system dependencies are still mostly manual-managed, but we have GYML_GNN_USER_INDEX_META in 'airflow/dags/batch/gyml/__init__.py:53', which controls index splits; we can check index_id against meta.


A:

• I’ll check the existing service smoke test and index metadata, then record what they cover and which dependencies remain manually managed.

• Confirmed: CI already starts the built image and checks version, readiness, and inference. That covers model loading and basic execution, while semantic compatibility still needs artifact/version lineage.

Recorded two checks in the design:

- Preserve service-image smoke testing with the selected model and pinned ML package.
- Validate `index_id` and requested split against `GYML_GNN_USER_INDEX_META`—currently `MLDE-479-nbclean` → `treatment`.

Cross-system activation remains manually managed; the metadata check doesn’t verify live routing.


Q:

› OK, file ready for me to review?


A:

• Yes—[MLDE-654-gyml-online-auto-design.md](/workspace/data/MLDE-654-gyml-online-auto-design.md) is ready for your review. Agreed directions and open contract details are marked separately.


Q:

› Good job, although a little excessive for first approach to design-doc, IMHO. Too many mot really important details, masking important decisions. But it will do for now, thanks.


A:

• Understood. Future design updates will lead with the architecture and important decisions, keeping detailed inventories and implementation questions separate so they don’t obscure the main design.


Q:

› Export today’s session, please


A:

• I’ll use the export-session-dialog skill to save today’s questions and replies without tool calls or command logs.

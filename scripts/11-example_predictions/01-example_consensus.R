library(dynbenchmark)
library(tidyverse)

experiment("11-example_predictions")

#' @example
#' metadata <- read_rds(result_file("metadata.rds", "01-datasets/01-real"))
#' metadata %>% filter(trajectory_type == "tree") %>% View
#'
#' load_datasets(list_datasets("synthetic/dyngen")$id) %>% filter(trajectory_type == "cycle") %>% pull(id)
#'

# load dataset
designs <- list(
  list(
    id = "linear",
    dataset_id = "real/developing-dendritic-cells_schlitzer",
    answers = dynguidelines::answer_questions(time = "5m", multiple_disconnected = FALSE, expect_topology = TRUE, expected_topology = "linear"),
    method_ids = c("scorpius", "monocle_ica", "slingshot", "paga", "waterfall", "tscan", "grandprix")
  ),
  list(
    id = "bifurcating",
    dataset_id = "real/fibroblast-reprogramming_treutlein",
    answers = dynguidelines::answer_questions(time = "5m", multiple_disconnected = FALSE, expect_topology = TRUE, expected_topology = "bifurcation"),
    method_ids = c("monocle_ddrtree", "slingshot", "paga", "pcreode", "scuba", "raceid_stemid", "dpt")
  ),
  list(
    id = "disconnected",
    # dataset_id = "real/placenta-trophoblast-differentiation-invasive_mca",
    dataset_id = "synthetic/dyntoy/disconnected_1",
    # dataset_id = "real/mouse-cell-atlas-combination-8",
    answers = dynguidelines::answer_questions(time = "1d", multiple_disconnected = TRUE, prior_information = "start_id", memory = "10GB"),
    method_ids = c("paga", "raceid_stemid", "gng")
  ),
  list(
    id = "cyclic",
    dataset_id = "synthetic/dyngen/72",
    # dataset_id = "synthetic/dyntoy/cyclic_1",
    # dataset_id = "real/cell-cycle_leng",
    answers = dynguidelines::answer_questions(time = "5m", multiple_disconnected = FALSE, expect_topology = TRUE, expected_topology = "cycle"),
    method_ids = c("angle", "paga", "gng")
  )
)
design <- designs[[2]]

plot_dimred_overviews <- list()

for (design in designs[-2]) {
  dataset <- load_dataset(design$dataset_id)

  dataset <- dataset %>% add_dimred(dyndimred::dimred_landmark_mds)
  # dataset <- dataset %>% add_dimred(dyndimred::dimred_umap)

  # plot reference dataset
  color_cells <- if (startsWith(dataset$source, "synthetic")) {"milestone"} else {"grouping"}
  milestones <- tibble(milestone_id = dataset$milestone_ids)
  plot_dimred_reference <- plot_dimred(
    dataset,
    color_cells,
    label_milestones = FALSE,
    dimred = get_dimred(dataset),
    milestones=milestones,
    trajectory_size = 1
  ) +
    labs(title = "Dataset", subtitle = "(with reference trajectory)") +
    theme(plot.subtitle = element_text(hjust = 0.5), legend.position = "none")
  plot_dimred_reference

  # get methods
  # guidelines <- dynguidelines::guidelines(dataset, answers = design$answers)
  # method_ids <- guidelines$methods_aggr$method_id[1:3] %>% gsub("projected_gng", "gng", .) %>% discard(is.na)
  method_ids <- design$method_ids

  # run methods
  models <- infer_trajectories(dataset, method_ids)
  models$model <- map(models$model, simplify_trajectory)

  # plot models
  dimred_plots <- models$model %>%
    map(plot_dimred, dimred = get_dimred(dataset), grouping = get_grouping(dataset), plot_milestone_network = TRUE) %>%
    map2(models$method_name, ~ . + ggtitle(.y) + theme(legend.position = "none")) %>%
    patchwork::wrap_plots()

  dimred_plots

  # get consensus
  models$model <- map(models$model, dynwrap::add_cell_waypoints) %>% map(simplify_trajectory)
  models$model_ix <- seq_len(nrow(models))

  model_combinations <- crossing(model_ix1 = models$model_ix, model_ix2 = models$model_ix)
  model_combinations$correlation <- map2_dbl(
    models$model[model_combinations$model_ix1],
    models$model[model_combinations$model_ix2],
    function(model1, model2) {
      # make sure that the cell ids match, TODO in dyneval: force this through a parameter
      model1$cell_ids <- dataset$cell_ids
      model2$cell_ids <- dataset$cell_ids
      dyneval::calculate_metrics(model1, model2, "correlation")$correlation
    }
  )
  model_combinations

  vote_mean <- function(model_combinations, metric) {
    metric <- rlang::enquo(metric)

    model_combinations %>%
      group_by(model_ix1) %>%
      filter(model_ix1 != model_ix2) %>%
      summarise(score = mean(!!metric)) %>%
      rename(model_ix = model_ix1)
  }

  vote_median <- function(model_combinations, metric) {
    metric <- rlang::enquo(metric)

    model_combinations %>%
      group_by(model_ix1) %>%
      filter(model_ix1 != model_ix2) %>%
      summarise(score = median(!!metric)) %>%
      rename(model_ix = model_ix1)
  }

  model_voting <- vote_median(model_combinations, correlation)

  ordered_models <- left_join(
    models,
    model_voting,
    "model_ix"
  ) %>%
    arrange(-score)

  # plot models
  plot_dimreds <- map(ordered_models$model, function(model) {
    print(1)
    plot_dimred(
      model,
      color_cells,
      grouping = get_grouping(dataset),
      milestone_percentages = dataset$milestone_percentages,
      milestones = milestones,
      dimred = get_dimred(dataset),
      plot_milestone_network = FALSE,
      cells_alpha = 0.5
    )
    # plot_dimred(model, dimred = get_dimred(dataset), plot_milestone_network = TRUE)
    # plot_dimred(model, "pseudotime", pseudotime = calculate_pseudotime(model %>% add_root(dataset$prior_information$start_id)), dimred = get_dimred(dataset), plot_milestone_network = TRUE)
    # plot_dimred(model, grouping = group_onto_trajectory_edges(model), color_cells = "grouping", dimred = get_dimred(dataset), plot_milestone_network = TRUE)
    # plot_dimred(model, grouping = group_onto_nearest_milestones(model), color_cells = "grouping", dimred = get_dimred(dataset), plot_milestone_network = TRUE)
    }) %>%
    map2(ordered_models$method_name, ~ . + ggtitle(.y)) %>%
    legend_at(theme_legend = guides(color = guide_legend(nrow = 1, ncol = length(unique(get_grouping(dataset))), title.theme = element_blank()))) %>%
    modify_at(1, ~ . + annotate("rect", xmin = -Inf, xmax = Inf, ymin = -Inf, ymax = Inf, fill = NA, color = "black") + labs(subtitle="(consensus prediction)") + theme(plot.subtitle = element_text(hjust = 0.5)))

  plot_dimred_overview <- plot_dimreds %>%
    c(list(plot_dimred_reference), .) %>%
    patchwork::wrap_plots(nrow = 1)

  plot_dimred_overview

  plot_dimred_overviews[[design$id]] <- plot_dimred_overview
}


plot_dimred_overviews <- plot_dimred_overviews %>% map(wrap_elements)

plot_example_predictions <- patchwork::wrap_plots(
  plot_dimred_overviews$linear + labs(tag = "a"),
  plot_dimred_overviews$bifurcating + labs(tag = "b"),
  patchwork::wrap_plots(
    plot_dimred_overviews$disconnected + labs(tag = "c"),
    plot_dimred_overviews$cyclic + labs(tag = "d"),
    ncol = 2
  ) %>% wrap_elements(),
  nrow = 3
)

write_rds(plot_example_predictions, result_file("example_predictions.rds"))
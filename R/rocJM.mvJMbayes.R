rocJM.mvJMbayes <- function (object, newdata, Tstart, Thoriz = NULL, Dt = NULL, 
                             idVar = "id", M = 100, ...) {
    if (!inherits(object, "mvJMbayes"))
        stop("Use only with 'mvJMbayes' objects.\n")
    if (!is.data.frame(newdata) || nrow(newdata) == 0)
        stop("'newdata' must be a data.frame with more than one rows.\n")
    if (is.null(newdata[[idVar]]))
        stop("'idVar' not in 'newdata'.\n")
    if (is.null(Thoriz) && is.null(Dt))
        stop("either 'Thoriz' or 'Dt' must be non null.\n")
    if (!is.null(Thoriz) && Thoriz <= Tstart)
        stop("'Thoriz' must be larger than 'Tstart'.")
    if (is.null(Thoriz))
        Thoriz <- Tstart + Dt
    Thoriz <- Thoriz + 1e-07
    id <- newdata[[idVar]]
    id <- match(id, unique(id))
    TermsT <- object$model_info$coxph_components$Terms
    environment(TermsT) <- parent.frame()#.GlobalEnv
    mframe <- model.frame(TermsT, newdata)
    if (length(na_ind <- attr(mframe, "na.action"))) {
        id <- id[-na_ind]
    }
    SurvT <- model.response(mframe) 
    is_counting <- attr(SurvT, "type") == "counting"
    is_interval <- attr(SurvT, "type") == "interval"
    Time <- if (is_counting) {
        ave(SurvT[, 2], id, FUN = function (x) tail(x, 1))
    } else if (is_interval) {
        Time1 <- SurvT[, "time1"]
        Time2 <- SurvT[, "time2"]
        Time <- Time1
        Time[Time2 != 1] <- Time2[Time2 != 1]
        Time
    } else {
        SurvT[, 1]
    }
    timeVar <- object$model_info$timeVar
    newdata2 <- newdata[Time > Tstart, ]
    newdata2 <- newdata2[newdata2[[timeVar]] <= Tstart, ]    
    pi.u.t <- if (is_counting) {
        survfitJM(object, newdata = newdata2, idVar = idVar, survTimes = Thoriz, 
                   M = M, LeftTrunc_var = all.vars(TermsT)[1L])
    } else {
        survfitJM(object, newdata = newdata2, idVar = idVar, survTimes = Thoriz, 
                  M = M)
    }
    pi.u.t <- sapply(pi.u.t$summaries, "[", 1, 2)
    # extract event process information
    id <- newdata2[[idVar]]
    SurvT <- model.response(model.frame(TermsT, newdata2)) 
    if (is_counting) {
        f <- factor(id, levels = unique(id))
        Time <- tapply(SurvT[, 2], f, tail, 1)
        event <- tapply(SurvT[, 3], f, tail, 1)
    } else if (is_interval) {
        Time1 <- SurvT[, "time1"]
        Time2 <- SurvT[, "time2"]
        Time <- Time1
        Time[Time2 != 1] <- Time2[Time2 != 1]
        Time <- Time[!duplicated(id)]
        event <- SurvT[!duplicated(id), "status"]
    } else {
        Time <- SurvT[!duplicated(id), 1]
        event <- SurvT[!duplicated(id), 2]
    }
    names(Time) <- names(event) <- as.character(unique(id))
    # subjects who died before Thoriz
    ind1 <- Time < Thoriz & (event == 1 | event == 3)
    # subjects who were censored in the interval (Tstart, Thoriz)
    ind2 <- Time < Thoriz & (event == 0 | event == 2)
    ind <- ind1 | ind2
    if (any(ind2)) {
        nams <- unique(names(ind2[ind2]))
        pi2 <- if (is_counting) {
            survfitJM(object, newdata = newdata2[id %in% nams, ], idVar = idVar, 
                      last.time = Time[nams], survTimes = Thoriz, 
                      M = M, LeftTrunc_var = all.vars(TermsT)[1L])
        } else {
            survfitJM(object, newdata = newdata2[id %in% nams, ], idVar = idVar, 
                      last.time = Time[nams], survTimes = Thoriz, M = M)
        }
        pi2 <- 1 - sapply(pi2$summaries, "[", 1, 2)
        nams2 <- names(ind2[ind2])
        ind[ind2] <- ind[ind2] * pi2[nams2]
    }
    # calculate sensitivity and specificity
    thrs <- seq(0, 1, length = 101)
    nTP <- colSums(outer(pi.u.t, thrs, "<") * c(ind)) 
    nFN <- sum(ind) - nTP
    TP <- nTP / sum(ind)
    nFP <- colSums(outer(pi.u.t, thrs, "<") * c(1 - ind)) 
    nTN <- sum(1 - ind) - nFP
    FP <- nFP / sum(1 - ind)
    Q <- colMeans(outer(pi.u.t, thrs, "<"))
    Q. <- 1 - Q
    k.1.0 <- (TP - Q) / Q.
    k.0.0 <- (1 - FP - Q.) / Q
    P <- mean(ind)
    P. <- 1 - P
    k.05.0 <- (P * Q. * k.1.0 + P. * Q * k.0.0) / (P * Q. + P. * Q)
    f1score <- 2 * nTP / (2 * nTP + nFN + nFP)
    F1score <- median(thrs[f1score == max(f1score)])
    youden <- TP - FP
    Youden <- median(thrs[youden == max(youden)])
    out <- list(TP = TP, FP = FP, nTP = nTP, nFN = nFN, nFP = nFP, nTN = nTN,
                qSN = k.1.0, qSP = k.0.0, qOverall = k.05.0, 
                thrs = thrs, 
                F1score = F1score, Youden = Youden,
                Tstart = Tstart, Thoriz = Thoriz, nr = length(unique(id)), 
                classObject = class(object), nameObject = deparse(substitute(object)))
    class(out) <- "rocJM"
    out
}

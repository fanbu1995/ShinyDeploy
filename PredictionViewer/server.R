# @file server.R
#
# Copyright 2018 Observational Health Data Sciences and Informatics
#
# This file is part of PatientLevelPrediction
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

library(shiny)
library(plotly)
library(shinycssloaders)

source("plots.R")
source("utils.R")

shiny::shinyServer(function(input, output, session) {
  session$onSessionEnded(stopApp)
  # reactive values - contains the location of the plpResult
  ##reactVars <- shiny::reactiveValues(resultLocation=NULL,
  ##                                   plpResult= NULL)
  reactVars <- list(plpResult=runPlp)
  
  # reset the row selection
  shiny::observeEvent(input$resetCharacter,
                      {DT::selectRows(proxy=DT::dataTableProxy(outputId='characterizationTab', 
                                                               deferUntilFlush=F), 
                                      selected=NULL)}
  )
  
  # create outputs 
  output$evalSummary <- DT::renderDataTable({
    if(is.null(reactVars$plpResult))
      return(NULL)
    
    returnTab <- as.data.frame(reactVars$plpResult$performanceEvaluation$evaluationStatistics)
    returnTab$Metric <- gsub('.auc','',returnTab$Metric)
    returnTab <- reshape2::dcast(returnTab[,-1], Metric ~ Eval, value.var = 'Value')
    
    # adding incidence
    oc <- returnTab[returnTab[,colnames(returnTab)=='Metric']=='outcomeCount',colnames(returnTab)!='Metric']
    pop <- returnTab[returnTab[,colnames(returnTab)=='Metric']=='populationSize',colnames(returnTab)!='Metric']
    inc <- c('Incidence',as.double(oc)/as.double(pop)*100)
    returnTab <- rbind(returnTab, inc)
    
    returnTab <-data.frame(Metric=returnTab[,colnames(returnTab)=='Metric'],
                           train=round_df(as.double(unlist(returnTab[,colnames(returnTab)=='train'])),3),
                           test=round_df(as.double(unlist(returnTab[,colnames(returnTab)=='test'])),3)
                           )
    returnTab[]
    
    #rownames(returnTab) <- 1:length(returnTab)
    
  },     escape = FALSE, selection = 'none',
  options = list(
    pageLength = 25,
    dom = 't',
    columnDefs = list(list(visible=FALSE, targets=0))
    #,initComplete = I("function(settings, json) {alert('Done.');}")
  ))
  
  # Covariate summary - add buttons to color by type
  output$characterization <- plotly::renderPlotly({
    if(is.null(reactVars$plpResult))
      return(NULL)
    plot <- plotCovSummary(reactVars,input)
   return(plot)
  })
  
  output$characterizationTab <- DT::renderDataTable({
    if(is.null(reactVars$plpResult))
      return(NULL)
    
    returnTab <- as.data.frame(reactVars$plpResult$covariateSummary)
    if(!is.null(returnTab$CovariateMeanWithOutcome)){
      returnTab$meanDifference <-returnTab$CovariateMeanWithOutcome- returnTab$CovariateMeanWithNoOutcome
      returnTab <- returnTab[,c('covariateName','CovariateMeanWithOutcome','CovariateMeanWithNoOutcome','meanDifference')]
    } else {
      returnTab <- returnTab[,c('covariateName','CovariateCountWithOutcome','CovariateCountWithNoOutcome')]
    }
    returnTab[,-1] <- formatC(as.double(unlist(returnTab[,-1])), digits=4,format = "f")
    returnTab
    
  },     escape = FALSE, #selection = 'none',
  options = list(
    pageLength = 25,
    columnDefs = list(list(visible=FALSE, targets=0))
  ))
  
  # ROCs
  output$rocPlotTest <- plotly::renderPlotly({
    if(is.null(reactVars$plpResult))
      return(NULL)
    #PatientLevelPrediction::plotSparseRoc(reactVars$plpResult$performanceEvaluation, 
    #                                      type='test')
    data <- reactVars$plpResult$performanceEvaluation$thresholdSummary[reactVars$plpResult$performanceEvaluation$thresholdSummary$Eval=='test',]
    plotly::plot_ly(x = 1-c(0,data$specificity,1)) %>%
      plotly::add_lines(y = c(1,data$sensitivity,0),name = "hv", 
                        text = paste('Risk Threshold:',c(0,data$predictionThreshold,1)),
                        line = list(shape = "hv",
                                    color = 'rgb(22, 96, 167)'),
                        fill = 'tozeroy') %>%
      plotly::add_trace(x= c(0,1), y = c(0,1),mode = 'lines',
                        line = list(dash = "dash"), color = I('black'),
                        type='scatter') %>%
      layout(title = "ROC Plot",
             xaxis = list(title = "1-specificity"),
             yaxis = list (title = "Sensitivity"),
             showlegend = FALSE)
  })
  output$rocPlotTrain <- plotly::renderPlotly({
    if(is.null(reactVars$plpResult))
      return(NULL)
    #PatientLevelPrediction::plotSparseRoc(reactVars$plpResult$performanceEvaluation, 
    #                                      type='train')
    data <- reactVars$plpResult$performanceEvaluation$thresholdSummary[reactVars$plpResult$performanceEvaluation$thresholdSummary$Eval=='train',]
    plotly::plot_ly(x = 1-c(0,data$specificity,1)) %>%
      plotly::add_lines(y = c(1,data$sensitivity,0),name = "hv", 
                        text = paste('Risk Threshold:',c(0,data$predictionThreshold,1)),
                        line = list(shape = "hv",
                                    color = 'rgb(22, 96, 167)'),
                        fill = 'tozeroy') %>%
      plotly::add_trace(x= c(0,1), y = c(0,1),mode = 'lines',
                        line = list(dash = "dash"), color = I('black'),
                        type='scatter') %>%
      layout(title = "ROC Plot",
             xaxis = list(title = "1-specificity"),
             yaxis = list (title = "Sensitivity"),
             showlegend = FALSE)
  })
  
  # Calibration
  output$calPlotTest <- plotly::renderPlotly({
    if(is.null(reactVars$plpResult))
      return(NULL)
    #PatientLevelPrediction::plotSparseCalibration(reactVars$plpResult$performanceEvaluation, 
    #                                      type='test')
    dataval <- reactVars$plpResult$performanceEvaluation$calibrationSummary[reactVars$plpResult$performanceEvaluation$calibrationSummary$Eval=='test',]
    dataval <- dataval[, c('averagePredictedProbability','observedIncidence', 'PersonCountAtRisk')]
    cis <- apply(dataval, 1, function(x) binom.test(x[2]*x[3], x[3], alternative = c("two.sided"), conf.level = 0.95)$conf.int)
    dataval$lci <- cis[1,]  
    dataval$uci <- cis[2,]
    dataval$ci <- dataval$observedIncidence-dataval$lci
    
    plotly::plot_ly(x = dataval$averagePredictedProbability) %>%
      plotly::add_markers(y = dataval$observedIncidence,
                          error_y = list(type = "data",
                                         array = dataval$ci,
                                         color = '#000000')) %>%
      plotly::add_trace(x= c(0,1), y = c(0,1),mode = 'lines',
                        line = list(dash = "dash"), color = I('black'),
                        type='scatter') %>%
      layout(title = "Calibration Plot",
             yaxis = list(title = "Observed Incidence",
                          range = c(0, 1.1*max(c(dataval$averagePredictedProbability,dataval$observedIncidence)))),
             xaxis = list (title = "Mean Predicted Risk",
                           range = c(0, 1.1*max(c(dataval$averagePredictedProbability,dataval$observedIncidence)))),
             showlegend = FALSE)
  })
  output$calPlotTrain <- plotly::renderPlotly({
    if(is.null(reactVars$plpResult))
      return(NULL)
    #PatientLevelPrediction::plotSparseCalibration(reactVars$plpResult$performanceEvaluation, 
    #                                      type='train')
    dataval <- reactVars$plpResult$performanceEvaluation$calibrationSummary[reactVars$plpResult$performanceEvaluation$calibrationSummary$Eval=='train',]
    dataval <- dataval[, c('averagePredictedProbability','observedIncidence', 'PersonCountAtRisk')]
    cis <- apply(dataval, 1, function(x) binom.test(x[2]*x[3], x[3], alternative = c("two.sided"), conf.level = 0.95)$conf.int)
    dataval$lci <- cis[1,]  
    dataval$uci <- cis[2,]
    dataval$ci <- dataval$observedIncidence-dataval$lci
    
    plotly::plot_ly(x = dataval$averagePredictedProbability) %>%
      plotly::add_markers(y = dataval$observedIncidence,
                          error_y = list(type = "data",
                                         array = dataval$ci,
                                         color = '#000000')) %>%
      plotly::add_trace(x= c(0,1), y = c(0,1),mode = 'lines',
                        line = list(dash = "dash"), color = I('black'),
                        type='scatter') %>%
      layout(title = "Calibration Plot",
             yaxis = list(title = "Observed Incidence",
                          range = c(0, 1.1*max(c(dataval$averagePredictedProbability,dataval$observedIncidence)))),
             xaxis = list (title = "Mean Predicted Risk",
                           range = c(0, 1.1*max(c(dataval$averagePredictedProbability,dataval$observedIncidence)))),
             showlegend = FALSE)
  })
  
  # Pref distributions
  output$prefPlotTest <- plotly::renderPlotly({
    if(is.null(reactVars$plpResult))
      return(NULL)
    print(
      ggplotly(plotPreferencePDF(reactVars$plpResult$performanceEvaluation,type='test'))
    )
  })
  output$prefPlotTrain <- plotly::renderPlotly({
    if(is.null(reactVars$plpResult))
      return(NULL)

    print(
      ggplotly(plotPreferencePDF(reactVars$plpResult$performanceEvaluation,type='train'))
    ) %>%
      layout(
        yaxis = list(
          hoverformat = '.2f'
        )
      )
  })
  
  # box plots
  output$boxPlotTest <- shiny::renderPlot({
    if(is.null(reactVars$plpResult))
      return(NULL)
    plotPredictionDistribution(reactVars$plpResult$performanceEvaluation, 
                                                      type='test')
  })
  output$boxPlotTrain <- shiny::renderPlot({
    if(is.null(reactVars$plpResult))
      return(NULL)
   plotPredictionDistribution(reactVars$plpResult$performanceEvaluation, 
                                                       type='train')
  
  })
  
  # demo calibration
  output$demoPlotTest <- plotly::renderPlotly({
    
    validate(
      need(is.null(reactVars$plpResult$performanceEvaluation$demographicSummary) == F, "Test demographics are not available")
    )
    if(is.null(reactVars$plpResult))
      return(NULL)
    #PatientLevelPrediction::plotDemographicSummary(reactVars$plpResult$performanceEvaluation, 
    #                                                   type='test')
    dataval <- reactVars$plpResult$performanceEvaluation$demographicSummary[reactVars$plpResult$performanceEvaluation$demographicSummary$Eval=='test',]
    dataval$averagePredictedProbability[is.na(dataval$averagePredictedProbability)] <- 0
    dataval$PersonCountAtRisk[is.na(dataval$PersonCountAtRisk)] <- 0
    dataval$PersonCountWithOutcome[is.na(dataval$PersonCountWithOutcome)] <- 0
    
    dataval$ageGroup2 <-gsub('Age group: ','',dataval$ageGroup)
    if(sum(c('Male','Female')%in%dataval$genGroup)==2)
    {
      dataval$ageGroup2 <- factor(dataval$ageGroup2,
                                  levels = dataval$ageGroup2[dataval$genGroup=='Male'][order(dataval$demographicId[dataval$genGroup=='Male'])])
      
      p1 <- plot_ly(x = dataval$ageGroup2[dataval$genGroup=='Male']) %>%
        add_lines(y = dataval$averagePredictedProbability[dataval$genGroup=='Male'],
                  error_y = list(value=dataval$StDevPredictedProbability[dataval$genGroup=='Male']),
                  name='Mean Predicted Risk',
                  line = list(color = 'rgb(22, 96, 167)')) %>%
        add_lines(y = dataval$PersonCountWithOutcome[dataval$genGroup=='Male']/dataval$PersonCountAtRisk[dataval$genGroup=='Male'],
                  name='Observed Risk',
                  line = list(color = 'rgb(205, 12, 24)')) %>%
        layout(yaxis = list(range = c(0,max(c(dataval$PersonCountWithOutcome/dataval$PersonCountAtRisk,dataval$averagePredictedProbability), na.rm =T)
        )),
        showlegend = FALSE)
      
      p2 <- plot_ly(x = dataval$ageGroup2[dataval$genGroup=='Female']) %>%
        add_lines(y = dataval$averagePredictedProbability[dataval$genGroup=='Female'],#error_y = list(value=dataval$StDevPredictedProbability[dataval$genGroup=='Male']),
                  error_y = list(value=dataval$StDevPredictedProbability[dataval$genGroup=='Female'],
                                 color = 'rgb(22, 96, 167)'),
                  name='Mean Predicted Risk',
                  line = list(color = 'rgb(22, 96, 167)')) %>%
        add_lines(y = dataval$PersonCountWithOutcome[dataval$genGroup=='Female']/dataval$PersonCountAtRisk[dataval$genGroup=='Female'],
                  name='Observed Risk',
                  line = list(color = 'rgb(205, 12, 24)')) %>%
        layout(yaxis = list(range = c(0,max(c(dataval$PersonCountWithOutcome/dataval$PersonCountAtRisk,dataval$averagePredictedProbability), na.rm =T)
        )),
        showlegend = FALSE)
      
      subplot(p1, p2) %>% 
        layout(annotations = list(
          list(x = 0.2 , y = 1.05, text = "Males", showarrow = F, xref='paper', yref='paper'),
          list(x = 0.8 , y = 1.05, text = "Females", showarrow = F, xref='paper', yref='paper')),
          title = 'Demographics Plot',
          yaxis = list(title = "Fraction",
                       range = c(0,max(c(dataval$PersonCountWithOutcome/dataval$PersonCountAtRisk,dataval$averagePredictedProbability), na.rm =T)
                       ))
        )
    } else if(sum(dataval$PersonCountAtRisk, na.rm = T)!=0){
      dataval$ageGroup2 <- factor(dataval$ageGroup2,
                                  levels = dataval$ageGroup2[order(dataval$demographicId)])
      
      plot_ly(x = dataval$ageGroup2) %>%
        add_lines(y = dataval$averagePredictedProbability,
                  error_y = list(value=dataval$StDevPredictedProbability,
                                 color = 'rgb(22, 96, 167)'),
                  name='Mean Predicted Risk',
                  line = list(color = 'rgb(22, 96, 167)')) %>%
        add_lines(y = dataval$PersonCountWithOutcome/dataval$PersonCountAtRisk,
                  name='Observed Risk',
                  line = list(color = 'rgb(205, 12, 24)')) %>%
        layout(yaxis = list(title = "Fraction",
                            range = c(0,max(c(dataval$PersonCountWithOutcome/dataval$PersonCountAtRisk,dataval$averagePredictedProbability), na.rm =T)
                            )),
               title = 'Demographics Plot (No Gender)',
               showlegend = FALSE)
      
    } else {
      return(NULL)
    }
    
  })
  output$demoPlotTrain <- plotly::renderPlotly({
    validate(
      need(is.null(reactVars$plpResult$performanceEvaluation$demographicSummary) == F, "Train demographics are not available")
    )
    if(is.null(reactVars$plpResult))
      return(NULL)
    #PatientLevelPrediction::plotDemographicSummary(reactVars$plpResult$performanceEvaluation, 
    #                                                   type='train')
    dataval <- reactVars$plpResult$performanceEvaluation$demographicSummary[reactVars$plpResult$performanceEvaluation$demographicSummary$Eval=='train',]
    dataval$averagePredictedProbability[is.na(dataval$averagePredictedProbability)] <- 0
    dataval$PersonCountAtRisk[is.na(dataval$PersonCountAtRisk)] <- 0
    dataval$PersonCountWithOutcome[is.na(dataval$PersonCountWithOutcome)] <- 0
    
    dataval$ageGroup2 <-gsub('Age group: ','',dataval$ageGroup)
    if(sum(c('Male','Female')%in%dataval$genGroup)==2)
    {
      dataval$ageGroup2 <- factor(dataval$ageGroup2,
                                  levels = dataval$ageGroup2[dataval$genGroup=='Male'][order(dataval$demographicId[dataval$genGroup=='Male'])])
      
      p1 <- plot_ly(x = dataval$ageGroup2[dataval$genGroup=='Male']) %>%
        add_lines(y = dataval$averagePredictedProbability[dataval$genGroup=='Male'],
                  error_y = list(value=dataval$StDevPredictedProbability[dataval$genGroup=='Male']),
                  name='Mean Predicted Risk',
                  line = list(color = 'rgb(22, 96, 167)')) %>%
        add_lines(y = dataval$PersonCountWithOutcome[dataval$genGroup=='Male']/dataval$PersonCountAtRisk[dataval$genGroup=='Male'],
                  name='Observed Risk',
                  line = list(color = 'rgb(205, 12, 24)')) %>%
        layout(yaxis = list(range = c(0,max(c(dataval$PersonCountWithOutcome/dataval$PersonCountAtRisk,dataval$averagePredictedProbability), na.rm =T)
        )),
        showlegend = FALSE)
      
      p2 <- plot_ly(x = dataval$ageGroup2[dataval$genGroup=='Female']) %>%
        add_lines(y = dataval$averagePredictedProbability[dataval$genGroup=='Female'],#error_y = list(value=dataval$StDevPredictedProbability[dataval$genGroup=='Male']),
                  error_y = list(value=dataval$StDevPredictedProbability[dataval$genGroup=='Female'],
                                 color = 'rgb(22, 96, 167)'),
                  name='Mean Predicted Risk',
                  line = list(color = 'rgb(22, 96, 167)')) %>%
        add_lines(y = dataval$PersonCountWithOutcome[dataval$genGroup=='Female']/dataval$PersonCountAtRisk[dataval$genGroup=='Female'],
                  name='Observed Risk',
                  line = list(color = 'rgb(205, 12, 24)')) %>%
        layout(yaxis = list(range = c(0,max(c(dataval$PersonCountWithOutcome/dataval$PersonCountAtRisk,dataval$averagePredictedProbability), na.rm =T)
        )),
        showlegend = FALSE)
      
      subplot(p1, p2) %>% 
        layout(annotations = list(
          list(x = 0.2 , y = 1.05, text = "Males", showarrow = F, xref='paper', yref='paper'),
          list(x = 0.8 , y = 1.05, text = "Females", showarrow = F, xref='paper', yref='paper')),
          title = 'Demographics Plot',
          yaxis = list(title = "Fraction",
                       range = c(0,max(c(dataval$PersonCountWithOutcome/dataval$PersonCountAtRisk,dataval$averagePredictedProbability), na.rm =T)
                       ))
        )
    } else if(sum(dataval$PersonCountAtRisk, na.rm = T)!=0){
      dataval$ageGroup2 <- factor(dataval$ageGroup2,
                                  levels = dataval$ageGroup2[order(dataval$demographicId)])
      
      plot_ly(x = dataval$ageGroup2) %>%
        add_lines(y = dataval$averagePredictedProbability,
                  error_y = list(value=dataval$StDevPredictedProbability,
                                 color = 'rgb(22, 96, 167)'),
                  name='Mean Predicted Risk',
                  line = list(color = 'rgb(22, 96, 167)')) %>%
        add_lines(y = dataval$PersonCountWithOutcome/dataval$PersonCountAtRisk,
                  name='Observed Risk',
                  line = list(color = 'rgb(205, 12, 24)')) %>%
        layout(yaxis = list(title = "Fraction",
                            range = c(0,max(c(dataval$PersonCountWithOutcome/dataval$PersonCountAtRisk,dataval$averagePredictedProbability), na.rm =T)
                            )),
               title = 'Demographics Plot (No Gender)',
               showlegend = FALSE)
      
    } else {
      return(NULL)
    }
  })
  
  
  
  
  # SETTINGS
  output$modelDetails <- DT::renderDataTable({
    if(is.null(reactVars$plpResult))
      return(NULL)
    
    returnTab <-data.frame(Model = reactVars$plpResult$inputSetting$modelSettings$name,
                           Test_Split = reactVars$plpResult$inputSetting$testSplit,
                           Test_Fraction = reactVars$plpResult$inputSetting$testFraction)
    typeRow <-data.frame(Setting = "Algorithm", Value = reactVars$plpResult$inputSetting$modelSettings$name)
    splitRow <- data.frame(Setting = "Test Split", Value = reactVars$plpResult$inputSetting$testSplit)
    splitFractionRow <-data.frame(Setting = "Test Fraction", Value = sprintf("%.2f",reactVars$plpResult$inputSetting$testFraction))
    hyperRows <- as.data.frame(reactVars$plpResult$model$hyperParamSearch)
    hyperRows <- cbind(rownames(hyperRows),hyperRows)
    colnames(hyperRows) <- c("Setting", "Value")
    rownames(hyperRows) <- NULL
    returnTab <- rbind(splitRow,splitFractionRow,typeRow,hyperRows)
    #colnames(returnTab) <- c("Algorithm","Test Split","Test Fraction")
    #,nfold=reactVars$plpResult$inputSetting$nfold)
    
  },     escape = FALSE, selection = 'none',
  options = list(
    pageLength = 25,
    dom = 't',
    columnDefs = list(list(visible=FALSE, targets=0))
    #,initComplete = I("function(settings, json) {alert('Done.');}")
  ))
  
  output$popDetails <- DT::renderDataTable({
    if(is.null(reactVars$plpResult))
      return(NULL)
    
    returnTab <- data.frame(Setting = names(reactVars$plpResult$inputSetting$populationSettings),
                            Value = unlist(lapply(reactVars$plpResult$inputSetting$populationSettings, 
                                                  function(x) paste(x, collapse=',', sep=','))))
    #remove attrition since we have tab now.
    returnTab <- subset(returnTab, Setting!="attrition")
    #returnTab <- returnTab[!returnTab$Value=="attrition"]
    rownames(returnTab) <- NULL
    return(returnTab)
  },     escape = FALSE, selection = 'none',
  options = list(
    pageLength = 25,
    dom = 't',
    columnDefs = list(list(visible=FALSE, targets=0))
    #,initComplete = I("function(settings, json) {alert('Done.');}")
  ))
  
  output$varDetails <- DT::renderDataTable({
    if(is.null(reactVars$plpResult))
      return(NULL)
    if(is.null(reactVars$plpResult$inputSetting$dataExtrractionSettings$covariateSettings))
      return(NULL)
    
    # if custom covs get the default one:
    if('getDbDefaultCovariateData' %in% 
       unlist(lapply(reactVars$plpResult$inputSetting$dataExtrractionSettings$covariateSettings, 
                     function(x) attr(x,"fun")))){
      ind <- which(unlist(lapply(reactVars$plpResult$inputSetting$dataExtrractionSettings$covariateSettings, 
                                 function(x) attr(x,"fun")))=='getDbDefaultCovariateData')
      reactVars$plpResult$inputSetting$dataExtrractionSettings$covariateSettings <- reactVars$plpResult$inputSetting$dataExtrractionSettings$covariateSettings[[ind]]
    }
    
    
    
    returnTab <- data.frame(Setting = names(reactVars$plpResult$inputSetting$dataExtrractionSettings$covariateSettings),
                            Value = unlist(lapply(reactVars$plpResult$inputSetting$dataExtrractionSettings$covariateSettings, function(x) paste(x, collapse='-'))))
    
    rownames(returnTab) <- NULL
    return(returnTab)  
  },     escape = FALSE, selection = 'none',
  options = list(
    pageLength = 100,
    dom = 't',
    columnDefs = list(list(visible=FALSE, targets=0))
    #,initComplete = I("function(settings, json) {alert('Done.');}")
  ))
  
  output$attrition <- DT::renderDataTable({
    if(is.null(reactVars$plpResult))
      return(NULL)
    
    returnTab <- reactVars$plpResult$model$populationSettings$attrition
    rownames(returnTab) <- NULL
    return(returnTab)
  },     escape = FALSE, selection = 'none',
  options = list(
    pageLength = 25,
    dom = 't',
    columnDefs = list(list(visible=FALSE, targets=0))
    #,initComplete = I("function(settings, json) {alert('Done.');}")
  ))
  
  # here 
  ## =================================================================================
  ##    EXTERNAL VALIDATION PLOTS
  ## =================================================================================
  output$characterizationTabVal <- DT::renderDataTable({
    validate(
      need(is.null(validatePlp) == F, "No validation data available \n")
    )
    if(is.null(validatePlp))
      return(NULL)
    
    if(length(validatePlp$validation)>1){
      valSummary <- c()
      for(i in 1:length(validatePlp$validation)){
        validatePlp$validation[[i]]$covariateSummary$meanDiff <- validatePlp$validation[[i]]$covariateSummary$CovariateMeanWithOutcome-
          validatePlp$validation[[i]]$covariateSummary$CovariateMeanWithNoOutcome
        voi <- validatePlp$validation[[i]]$covariateSummary[,c('covariateId','covariateName','meanDiff')]
        voi$database <- names(validatePlp$validation)[i]
        valSummary <- rbind(voi, valSummary)
      }
      valSummary$covariateName <- as.character(valSummary$covariateName)
      valSummary <- reshape2::dcast(valSummary, covariateId+covariateName~database, value.var = 'meanDiff')
      valSummary[,-c(1,2)] <- formatC(as.double(unlist(valSummary[,-c(1,2)])), digits=4,format = "f")
      #valSummary
      merge(reactVars$plpResult$covariateSummary[,c('covariateId','covariateValue')],valSummary, by='covariateId')
    } else {
      merge(reactVars$plpResult$covariateSummary[,c('covariateId','covariateValue')],validatePlp$validation[[1]]$covariateSummary, by='covariateId')
      
    }
  },     escape = FALSE, selection = 'none',
  options = list(
    pageLength = 25
  ))
  
  output$evalSummaryVal <- DT::renderDataTable({
    validate(
      need(is.null(validatePlp) == F, "No validation data available")
    )
    if(is.null(validatePlp))
      return(NULL)
    
    
    validatePlp$summary$Incidence <- as.double(as.character(validatePlp$summary$outcomeCount))/as.double(as.character(validatePlp$summary$populationSize))
    # format to 3dp
    for(col in colnames(validatePlp$summary)[!colnames(validatePlp$summary)%in%c('Database','outcomeCount','populationSize')])
      class(validatePlp$summary[,col]) <- 'numeric'
    is.num <- sapply(validatePlp$summary, is.numeric)
    validatePlp$summary[is.num] <- apply(validatePlp$summary[is.num],2,  round, 3)
    
    returnTab <- t(as.data.frame(validatePlp$summary))
  },     escape = FALSE, selection = 'none',
  options = list(
    pageLength = 25
    #,initComplete = I("function(settings, json) {alert('Done.');}")
  ))
  
  output$rocPlotVal <- plotly::renderPlotly({
    validate(
      need(is.null(validatePlp) == F, "No validation data available")
    )
    if(is.null(validatePlp))
      return(NULL)
    #PatientLevelPrediction::plotSparseRoc(reactVars$plpResult$performanceEvaluation, 
    #                                      type='train')
    rocPlotVal <- list()
    length(rocPlotVal) <- length(validatePlp$validation)
    for(i in 1:length(validatePlp$validation)){
      data <- validatePlp$validation[[i]]$performanceEvaluation$thresholdSummary
      rocPlotVal[[i]] <- plotly::plot_ly(x = 1-c(0,data$specificity,1)) %>%
        plotly::add_lines(y = c(1,data$sensitivity,0),name = "hv", 
                          text = paste('Risk Threshold:',c(0,data$predictionThreshold,1)),
                          line = list(shape = "hv",
                                      color = 'rgb(22, 96, 167)'),
                          fill = 'tozeroy') %>%
        plotly::add_trace(x= c(0,1), y = c(0,1),mode = 'lines',
                          line = list(dash = "dash"), color = I('black'),
                          type='scatter') %>%
        plotly::layout(annotations = list(text = names(validatePlp$validation)[i],
                                          xref = "paper", yref = "paper", yanchor = "bottom",xanchor = "center",
                                          align = "center",x = 0.5,y = 1,showarrow = FALSE))
      
    }
    p <- do.call(plotly::subplot, rocPlotVal)
    p %>% plotly::layout(xaxis = list(title = "1-specificity"),
                         yaxis = list (title = "Sensitivity"),
                         showlegend = FALSE)
  })
  
  output$calPlotVal <- plotly::renderPlotly({
    validate(
      need(is.null(validatePlp) == F, "No validation data available")
    )
    if(is.null(validatePlp))
      return(NULL)
    
    calPlotVal <- list()
    length(calPlotVal) <- length(validatePlp$validation)
    for(i in 1:length(validatePlp$validation)){
      data <- validatePlp$validation[[i]]$performanceEvaluation$calibrationSummary
      data <- data[, c('averagePredictedProbability','observedIncidence', 'PersonCountAtRisk')]
      cis <- apply(data, 1, function(x) binom.test(x[2]*x[3], x[3], alternative = c("two.sided"), conf.level = 0.95)$conf.int)
      data$lci <- cis[1,]  
      data$uci <- cis[2,]
      data$ci <- data$observedIncidence-data$lci
      
      calPlotVal[[i]] <- plotly::plot_ly(x = data$averagePredictedProbability) %>%
        plotly::add_markers(y = data$observedIncidence,
                            error_y = list(type = "data",
                                           array = data$ci,
                                           color = '#000000')) %>%
        plotly::add_trace(x= c(0,1), y = c(0,1),mode = 'lines',
                          line = list(dash = "dash"), color = I('black'),
                          type='scatter') %>%
        plotly::layout(annotations = list(text = names(validatePlp$validation)[i],
                                          xref = "paper", yref = "paper", yanchor = "bottom",xanchor = "center",
                                          align = "center",x = 0.5,y = 1,showarrow = FALSE),
                       yaxis = list(range = c(0, 1.1*max(c(data$averagePredictedProbability,data$observedIncidence)))),
                       xaxis = list (range = c(0, 1.1*max(c(data$averagePredictedProbability,data$observedIncidence))))
        )
      
    }
    p <- do.call(plotly::subplot, calPlotVal)
    
    p %>% plotly::layout(yaxis = list(title = "Observed Incidence"),
                         xaxis = list (title = "Mean Predicted Risk"),
                         showlegend = FALSE)
    
  })
  
})


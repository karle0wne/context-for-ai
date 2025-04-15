
FILE: ./src/main/java/dev/vality/disputes/DisputesApiApplication.java
MD5:  43f3efb77ccabd0dbed189d78b3403e0
SHA1: 16066af55403b2ab7485d3c51ef0f20be3cd39c1
package dev.vality.disputes;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;

@EnableAsync
@EnableScheduling
@ServletComponentScan
@SpringBootApplication(scanBasePackages = {"dev.vality.disputes", "dev.vality.swag"})
public class DisputesApiApplication extends SpringApplication {

    public static void main(String[] args) {
        SpringApplication.run(DisputesApiApplication.class, args);
    }

}


FILE: ./src/main/java/dev/vality/disputes/admin/callback/CallbackNotifier.java
MD5:  1c8c01f51ba8391998510c416c0a8626
SHA1: 6cfe3ca574a047922a32ee0c06dab04095914b26
package dev.vality.disputes.admin.callback;

import dev.vality.disputes.domain.tables.pojos.Dispute;

public interface CallbackNotifier {

    void sendDisputeAlreadyCreated(Dispute dispute);

    void sendDisputePoolingExpired(Dispute dispute);

    void sendDisputeManualPending(Dispute dispute, String errorMessage);

}


FILE: ./src/main/java/dev/vality/disputes/admin/callback/DisputesTgBotCallbackNotifierImpl.java
MD5:  867d556c1a9a9feb1d4325792e135df1
SHA1: 4ff2546e38c7756235fc98c8845295096865f1ae
package dev.vality.disputes.admin.callback;

import dev.vality.disputes.admin.DisputeAlreadyCreated;
import dev.vality.disputes.admin.DisputeManualPending;
import dev.vality.disputes.admin.DisputePoolingExpired;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.service.external.DisputesTgBotService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(value = "service.disputes-tg-bot.admin.enabled", havingValue = "true", matchIfMissing = true)
@RequiredArgsConstructor
@Slf4j
@SuppressWarnings({"LineLength"})
public class DisputesTgBotCallbackNotifierImpl implements CallbackNotifier {

    private final DisputesTgBotService disputesTgBotService;

    @Override
    public void sendDisputeAlreadyCreated(Dispute dispute) {
        disputesTgBotService.sendDisputeAlreadyCreated(getAlreadyCreated(dispute));
    }

    @Override
    public void sendDisputePoolingExpired(Dispute dispute) {
        disputesTgBotService.sendDisputePoolingExpired(getPoolingExpired(dispute));
    }

    @Override
    public void sendDisputeManualPending(Dispute dispute, String errorMessage) {
        disputesTgBotService.sendDisputeManualPending(getManualPending(dispute).setErrorMessage(errorMessage));
    }

    private DisputeManualPending getManualPending(Dispute dispute) {
        return new DisputeManualPending(dispute.getInvoiceId(), dispute.getPaymentId())
                .setErrorMessage(dispute.getErrorMessage());
    }

    private DisputeAlreadyCreated getAlreadyCreated(Dispute dispute) {
        return new DisputeAlreadyCreated(dispute.getInvoiceId(), dispute.getPaymentId());
    }

    private DisputePoolingExpired getPoolingExpired(Dispute dispute) {
        return new DisputePoolingExpired(dispute.getInvoiceId(), dispute.getPaymentId());
    }
}


FILE: ./src/main/java/dev/vality/disputes/admin/callback/DummyCallbackNotifierImpl.java
MD5:  729d486c8f827e107defac3b3d0b165d
SHA1: b9c31fc069c15f7010bb5f9ba7001cfa6968eb08
package dev.vality.disputes.admin.callback;

import dev.vality.disputes.domain.tables.pojos.Dispute;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(value = "service.disputes-tg-bot.admin.enabled", havingValue = "false")
@RequiredArgsConstructor
@Slf4j
@SuppressWarnings({"LineLength"})
public class DummyCallbackNotifierImpl implements CallbackNotifier {

    @Override
    public void sendDisputeAlreadyCreated(Dispute dispute) {
        log.debug("Trying to call DummyCallbackNotifierImpl.sendDisputeAlreadyCreated() {}", dispute.getId());
    }

    @Override
    public void sendDisputePoolingExpired(Dispute dispute) {
        log.debug("Trying to call DummyCallbackNotifierImpl.sendDisputePoolingExpired() {}", dispute.getId());
    }

    @Override
    public void sendDisputeManualPending(Dispute dispute, String errorMessage) {
        log.debug("Trying to call DummyCallbackNotifierImpl.sendDisputeManualPending() {} {}", dispute.getId(), errorMessage);
    }

}


FILE: ./src/main/java/dev/vality/disputes/admin/management/AdminManagementDisputesService.java
MD5:  5ee6d0cf9a61804c5c0d2178e0a44e17
SHA1: 0c62301fab8fdd795e631026a80910280ed26ad5
package dev.vality.disputes.admin.management;

import dev.vality.adapter.flow.lib.model.PollingInfo;
import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.disputes.admin.*;
import dev.vality.disputes.dao.FileMetaDao;
import dev.vality.disputes.dao.ProviderDisputeDao;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.domain.tables.pojos.ProviderDispute;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.polling.ExponentialBackOffPollingServiceWrapper;
import dev.vality.disputes.polling.PollingInfoService;
import dev.vality.disputes.provider.DisputeStatusResult;
import dev.vality.disputes.provider.DisputeStatusSuccessResult;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.disputes.schedule.result.DisputeStatusResultHandler;
import dev.vality.disputes.schedule.service.ProviderDataService;
import dev.vality.disputes.service.DisputesService;
import dev.vality.disputes.service.external.FileStorageService;
import dev.vality.disputes.service.external.InvoicingService;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.impl.classic.AbstractHttpClientResponseHandler;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.HttpEntity;
import org.apache.hc.core5.http.io.entity.EntityUtils;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Optional;

import static dev.vality.disputes.service.DisputesService.DISPUTE_PENDING_STATUSES;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class AdminManagementDisputesService {

    private final ProviderDisputeDao providerDisputeDao;
    private final FileMetaDao fileMetaDao;
    private final FileStorageService fileStorageService;
    private final DisputesService disputesService;
    private final ProviderDataService providerDataService;
    private final PollingInfoService pollingInfoService;
    private final InvoicingService invoicingService;
    private final ExponentialBackOffPollingServiceWrapper exponentialBackOffPollingService;
    private final DisputeStatusResultHandler disputeStatusResultHandler;
    private final CloseableHttpClient httpClient;

    @Transactional
    public void cancelPendingDispute(CancelParams params) {
        var dispute = disputesService.getSkipLockedByInvoiceId(params.getInvoiceId(), params.getPaymentId());
        if (DISPUTE_PENDING_STATUSES.contains(dispute.getStatus())) {
            // используется не failed, а cancelled чтоб можно было понять, что зафейлен по внешнему вызову
            disputesService.finishCancelled(
                    dispute,
                    params.getMapping().orElse(null),
                    params.getCancelReason().orElse(null));
        }
    }

    @Transactional
    public void approvePendingDispute(ApproveParams params) {
        var dispute = disputesService.getSkipLockedByInvoiceId(params.getInvoiceId(), params.getPaymentId());
        var changedAmount = params.getChangedAmount()
                .filter(s -> dispute.getStatus() == DisputeStatus.pending
                        || dispute.getStatus() == DisputeStatus.manual_pending
                        || dispute.getStatus() == DisputeStatus.pooling_expired)
                .orElse(null);
        if ((dispute.getStatus() == DisputeStatus.pending
                || dispute.getStatus() == DisputeStatus.manual_pending
                || dispute.getStatus() == DisputeStatus.pooling_expired)
                && !params.isSkipCallHgForCreateAdjustment()) {
            var invoicePayment = invoicingService.getInvoicePayment(dispute.getInvoiceId(), dispute.getPaymentId());
            var providerData = providerDataService.getProviderData(dispute.getProviderId(), dispute.getTerminalId());
            // если ProviderPaymentsUnexpectedPaymentStatus то нехрен апрувить не успешный платеж
            handleSucceededResultWithCreateAdjustment(dispute, changedAmount, providerData, invoicePayment.getLastTransactionInfo());
        } else if (dispute.getStatus() == DisputeStatus.pending
                || dispute.getStatus() == DisputeStatus.manual_pending
                || dispute.getStatus() == DisputeStatus.pooling_expired
                || dispute.getStatus() == DisputeStatus.create_adjustment) {
            disputesService.finishSucceeded(dispute, changedAmount);
        }
    }

    @Transactional
    public void bindCreatedDispute(BindParams params) {
        var disputeId = params.getDisputeId();
        var dispute = disputesService.getSkipLocked(disputeId);
        var providerDisputeId = params.getProviderDisputeId();
        if (dispute.getStatus() == DisputeStatus.already_exist_created) {
            providerDisputeDao.save(providerDisputeId, dispute);
            var providerData = providerDataService.getProviderData(dispute.getProviderId(), dispute.getTerminalId());
            disputesService.setNextStepToPending(dispute, providerData);
        }
    }

    @SneakyThrows
    public Dispute getDispute(DisputeParams params, boolean withAttachments) {
        var dispute = disputesService.getByInvoiceId(params.getInvoiceId(), params.getPaymentId());
        var disputeResult = new Dispute();
        disputeResult.setDisputeId(dispute.getId().toString());
        disputeResult.setProviderDisputeId(getProviderDispute(dispute)
                .map(ProviderDispute::getProviderDisputeId)
                .orElse(null));
        disputeResult.setInvoiceId(dispute.getInvoiceId());
        disputeResult.setPaymentId(dispute.getPaymentId());
        disputeResult.setProviderTrxId(dispute.getProviderTrxId());
        disputeResult.setStatus(dispute.getStatus().name());
        disputeResult.setErrorMessage(dispute.getErrorMessage());
        disputeResult.setMapping(dispute.getMapping());
        disputeResult.setAmount(String.valueOf(dispute.getAmount()));
        disputeResult.setChangedAmount(Optional.ofNullable(dispute.getChangedAmount())
                .map(String::valueOf)
                .orElse(null));
        log.debug("Dispute getDispute {}", disputeResult);
        if (!withAttachments) {
            return disputeResult;
        }
        try {
            disputeResult.setAttachments(new ArrayList<>());
            for (var disputeFile : fileMetaDao.getDisputeFiles(dispute.getId())) {
                var downloadUrl = fileStorageService.generateDownloadUrl(disputeFile.getFileId());
                var data = httpClient.execute(
                        new HttpGet(downloadUrl),
                        new AbstractHttpClientResponseHandler<byte[]>() {
                            @Override
                            public byte[] handleEntity(HttpEntity entity) throws IOException {
                                return EntityUtils.toByteArray(entity);
                            }
                        });
                disputeResult.getAttachments().get().add(new Attachment().setData(data));
            }
        } catch (NotFoundException ex) {
            log.warn("NotFound when handle AdminManagementDisputesService.getDispute, type={}", ex.getType(), ex);
        }
        return disputeResult;
    }

    @Transactional
    public void setPendingForPoolingExpiredDispute(SetPendingForPoolingExpiredParams params) {
        var dispute = disputesService.getSkipLockedByInvoiceId(params.getInvoiceId(), params.getPaymentId());
        if (dispute.getStatus() == DisputeStatus.pooling_expired) {
            var providerData = providerDataService.getProviderData(dispute.getProviderId(), dispute.getTerminalId());
            var pollingInfo = pollingInfoService.initPollingInfo(providerData.getOptions());
            dispute.setNextCheckAfter(getNextCheckAfter(providerData, pollingInfo));
            dispute.setPollingBefore(getLocalDateTime(pollingInfo.getMaxDateTimePolling()));
            disputesService.setNextStepToPending(dispute, providerData);
        }
    }

    private Optional<ProviderDispute> getProviderDispute(dev.vality.disputes.domain.tables.pojos.Dispute dispute) {
        try {
            return Optional.of(providerDisputeDao.get(dispute.getId()));
        } catch (NotFoundException ex) {
            log.warn("NotFound when handle AdminManagementDisputesService.getDispute, type={}", ex.getType(), ex);
            return Optional.empty();
        }
    }

    private void handleSucceededResultWithCreateAdjustment(
            dev.vality.disputes.domain.tables.pojos.Dispute dispute, Long changedAmount, ProviderData providerData, TransactionInfo transactionInfo) {
        disputeStatusResultHandler.handleSucceededResult(dispute, getDisputeStatusResult(changedAmount), providerData, transactionInfo);
    }

    private DisputeStatusResult getDisputeStatusResult(Long changedAmount) {
        return Optional.ofNullable(changedAmount)
                .map(amount -> DisputeStatusResult.statusSuccess(new DisputeStatusSuccessResult().setChangedAmount(amount)))
                .orElse(DisputeStatusResult.statusSuccess(new DisputeStatusSuccessResult()));
    }

    private LocalDateTime getLocalDateTime(Instant instant) {
        return LocalDateTime.ofInstant(instant, ZoneOffset.UTC);
    }

    private LocalDateTime getNextCheckAfter(ProviderData providerData, PollingInfo pollingInfo) {
        return exponentialBackOffPollingService.prepareNextPollingInterval(pollingInfo, providerData.getOptions());
    }
}


FILE: ./src/main/java/dev/vality/disputes/admin/management/AdminManagementHandler.java
MD5:  fabb307e826656d5a302f655fa99a8e2
SHA1: 602b8aa3e394410917f1c21cb8cf88439db43d2a
package dev.vality.disputes.admin.management;

import dev.vality.disputes.admin.*;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.schedule.core.NotificationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.ArrayList;

@Service
@RequiredArgsConstructor
@Slf4j
@SuppressWarnings({"LineLength"})
public class AdminManagementHandler implements AdminManagementServiceSrv.Iface {

    private final AdminManagementDisputesService adminManagementDisputesService;
    private final NotificationService notificationService;

    @Override
    public void cancelPending(CancelParamsRequest cancelParamsRequest) {
        log.info("Got cancelParamsRequest {}", cancelParamsRequest);
        for (var cancelParam : cancelParamsRequest.getCancelParams()) {
            try {
                adminManagementDisputesService.cancelPendingDispute(cancelParam);
            } catch (NotFoundException ex) {
                log.warn("NotFound when handle CancelParamsRequest, type={}", ex.getType(), ex);
            }
        }
        log.debug("Finish cancelParamsRequest {}", cancelParamsRequest);
    }

    @Override
    public void approvePending(ApproveParamsRequest approveParamsRequest) {
        log.info("Got approveParamsRequest {}", approveParamsRequest);
        for (var approveParam : approveParamsRequest.getApproveParams()) {
            try {
                adminManagementDisputesService.approvePendingDispute(approveParam);
            } catch (NotFoundException ex) {
                log.warn("NotFound when handle ApproveParamsRequest, type={}", ex.getType(), ex);
            }
        }
        log.debug("Finish approveParamsRequest {}", approveParamsRequest);
    }

    @Override
    public void bindCreated(BindParamsRequest bindParamsRequest) {
        log.info("Got bindParamsRequest {}", bindParamsRequest);
        for (var bindParam : bindParamsRequest.getBindParams()) {
            try {
                adminManagementDisputesService.bindCreatedDispute(bindParam);
            } catch (NotFoundException ex) {
                log.warn("NotFound when handle BindParamsRequest, type={}", ex.getType(), ex);
            }
        }
        log.debug("Finish bindParamsRequest {}", bindParamsRequest);
    }

    @Override
    public DisputeResult getDisputes(DisputeParamsRequest disputeParamsRequest) {
        log.info("Got disputeParamsRequest {}", disputeParamsRequest);
        var disputeResult = new DisputeResult(new ArrayList<>());
        for (var disputeParams : disputeParamsRequest.getDisputeParams()) {
            try {
                var dispute = adminManagementDisputesService.getDispute(disputeParams, disputeParamsRequest.isWithAttachments());
                disputeResult.getDisputes().add(dispute);
            } catch (NotFoundException ex) {
                log.warn("NotFound when handle DisputeParamsRequest, type={}", ex.getType(), ex);
            }
        }
        log.debug("Finish disputeParamsRequest {}", disputeParamsRequest);
        return disputeResult;
    }

    @Override
    public void setPendingForPoolingExpired(SetPendingForPoolingExpiredParamsRequest setPendingForPoolingExpiredParamsRequest) {
        log.info("Got setPendingForPoolingExpiredParamsRequest {}", setPendingForPoolingExpiredParamsRequest);
        for (var setPendingForPoolingExpiredParams : setPendingForPoolingExpiredParamsRequest.getSetPendingForPoolingExpiredParams()) {
            try {
                adminManagementDisputesService.setPendingForPoolingExpiredDispute(setPendingForPoolingExpiredParams);
            } catch (NotFoundException ex) {
                log.warn("NotFound when handle SetPendingForPoolingExpiredParamsRequest, type={}", ex.getType(), ex);
            }
        }
        log.debug("Finish setPendingForPoolingExpiredParamsRequest {}", setPendingForPoolingExpiredParamsRequest);
    }

    @Override
    public void sendMerchantsNotification(MerchantsNotificationParamsRequest params) {
        log.info("Got sendMerchantsNotification {}", params);
        notificationService.sendMerchantsNotification(params);
        log.debug("Finish sendMerchantsNotification {}", params);
    }
}


FILE: ./src/main/java/dev/vality/disputes/api/DisputesApiDelegate.java
MD5:  9e77b943b6d4d7e960654c9fdf9c4a15
SHA1: cde453d3d5e3053154c4d4b250f1b5ed4d326238
package dev.vality.disputes.api;

import dev.vality.swag.disputes.api.CreateApiDelegate;
import dev.vality.swag.disputes.api.StatusApiDelegate;
import dev.vality.swag.disputes.model.Create200Response;
import dev.vality.swag.disputes.model.CreateRequest;
import dev.vality.swag.disputes.model.Status200Response;
import org.springframework.http.ResponseEntity;
import org.springframework.web.context.request.NativeWebRequest;

import java.util.Optional;

@SuppressWarnings({"LineLength"})
public interface DisputesApiDelegate extends CreateApiDelegate, StatusApiDelegate {

    ResponseEntity<Create200Response> create(CreateRequest req, boolean checkUserAccessData);

    ResponseEntity<Status200Response> status(String disputeId, boolean checkUserAccessData);

    @Override
    default Optional<NativeWebRequest> getRequest() {
        return Optional.empty();
    }
}


FILE: ./src/main/java/dev/vality/disputes/api/DisputesApiDelegateService.java
MD5:  8cef921945edcafebb2a9ed7c992a321
SHA1: ea729d2aa3b597703b903ff48c581dfd710b4378
package dev.vality.disputes.api;

import dev.vality.disputes.api.converter.Status200ResponseConverter;
import dev.vality.disputes.api.service.ApiDisputesService;
import dev.vality.disputes.api.service.PaymentParamsBuilder;
import dev.vality.disputes.security.AccessService;
import dev.vality.swag.disputes.model.Create200Response;
import dev.vality.swag.disputes.model.CreateRequest;
import dev.vality.swag.disputes.model.Status200Response;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class DisputesApiDelegateService implements DisputesApiDelegate {

    private final PaymentParamsBuilder paymentParamsBuilder;
    private final AccessService accessService;
    private final ApiDisputesService apiDisputesService;
    private final Status200ResponseConverter status200ResponseConverter;

    @Override
    public ResponseEntity<Create200Response> create(CreateRequest createRequest) {
        return create(createRequest, true);
    }

    @Override
    public ResponseEntity<Create200Response> create(CreateRequest req, boolean checkUserAccessData) {
        log.info("-> Req: {}, invoiceId={}, paymentId={}, source={}", "/create", req.getInvoiceId(), req.getPaymentId(), checkUserAccessData ? "api" : "merchThrift");
        var accessData = accessService.approveUserAccess(req.getInvoiceId(), req.getPaymentId(), checkUserAccessData, true);
        // диспут по платежу может быть открытым только один за раз, если существует, отдаем действующий
        var dispute = apiDisputesService.checkExistBeforeCreate(req.getInvoiceId(), req.getPaymentId());
        if (dispute.isPresent()) {
            log.debug("<- Res existing: {}, invoiceId={}, paymentId={}", "/create", req.getInvoiceId(), req.getPaymentId());
            return ResponseEntity.ok(new Create200Response(String.valueOf(dispute.get().getId())));
        }
        var paymentParams = paymentParamsBuilder.buildGeneralPaymentContext(accessData);
        var disputeId = apiDisputesService.createDispute(req, paymentParams);
        log.debug("<- Res: {}, invoiceId={}, paymentId={}, source={}", "/create", req.getInvoiceId(), req.getPaymentId(), checkUserAccessData ? "api" : "merchThrift");
        return ResponseEntity.ok(new Create200Response(String.valueOf(disputeId)));
    }

    @Override
    public ResponseEntity<Status200Response> status(String disputeId) {
        return status(disputeId, true);
    }

    @Override
    public ResponseEntity<Status200Response> status(String disputeId, boolean checkUserAccessData) {
        var dispute = apiDisputesService.getDispute(disputeId);
        log.info("-> Req: {}, invoiceId={}, paymentId={}, disputeId={}, source={}", "/status", dispute.getInvoiceId(), dispute.getPaymentId(), disputeId, checkUserAccessData ? "api" : "merchThrift");
        accessService.approveUserAccess(dispute.getInvoiceId(), dispute.getPaymentId(), checkUserAccessData, false);
        var body = status200ResponseConverter.convert(dispute);
        log.debug("<- Res: {}, invoiceId={}, paymentId={}, disputeId={}, source={}", "/status", dispute.getInvoiceId(), dispute.getPaymentId(), disputeId, checkUserAccessData ? "api" : "merchThrift");
        return ResponseEntity.ok(body);
    }
}


FILE: ./src/main/java/dev/vality/disputes/api/controller/ErrorControllerAdvice.java
MD5:  04e939e95b41bb7227007d41af44475e
SHA1: 06aaa6a78ecce0218f790bd6d114ead3525dff4f
package dev.vality.disputes.api.controller;

import dev.vality.disputes.exception.AuthorizationException;
import dev.vality.disputes.exception.InvoicingPaymentStatusRestrictionsException;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.exception.TokenKeeperException;
import dev.vality.swag.disputes.model.GeneralError;
import jakarta.validation.ConstraintViolationException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.InvalidMediaTypeException;
import org.springframework.http.ResponseEntity;
import org.springframework.util.CollectionUtils;
import org.springframework.util.InvalidMimeTypeException;
import org.springframework.web.HttpMediaTypeNotAcceptableException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.context.request.WebRequest;

import java.net.http.HttpTimeoutException;
import java.util.stream.Collectors;

import static org.springframework.http.ResponseEntity.status;

@Slf4j
@RestControllerAdvice
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ErrorControllerAdvice {

    // ----------------- 4xx -----------------------------------------------------

    @ExceptionHandler({InvoicingPaymentStatusRestrictionsException.class})
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Object handleInvoicingPaymentStatusRestrictionsException(InvoicingPaymentStatusRestrictionsException ex) {
        log.warn("<- Res [400]: Payment should be failed", ex);
        return new GeneralError()
                .message("Blocked: Payment should be failed");
    }

    @ExceptionHandler({InvalidMimeTypeException.class})
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Object handleInvalidMimeTypeException(InvalidMimeTypeException ex) {
        log.warn("<- Res [400]: MimeType not valid", ex);
        return new GeneralError()
                .message(ex.getMessage());
    }

    @ExceptionHandler({InvalidMediaTypeException.class})
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Object handleInvalidMediaTypeException(InvalidMediaTypeException ex) {
        log.warn("<- Res [400]: MimeType not valid", ex);
        return new GeneralError()
                .message(ex.getMessage());
    }

    @ExceptionHandler({ConstraintViolationException.class})
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Object handleConstraintViolationException(ConstraintViolationException ex) {
        log.warn("<- Res [400]: Not valid", ex);
        var errorMessage = ex.getConstraintViolations().stream()
                .map(violation -> violation.getPropertyPath() + ": " + violation.getMessage())
                .collect(Collectors.joining(", "));
        return new GeneralError()
                .message(errorMessage);
    }

    @ExceptionHandler({MethodArgumentNotValidException.class})
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Object handleMethodArgumentNotValidException(MethodArgumentNotValidException ex) {
        log.warn("<- Res [400]: MethodArgument not valid", ex);
        return new GeneralError()
                .message(ex.getMessage());
    }

    @ExceptionHandler({MissingServletRequestParameterException.class})
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Object handleMissingServletRequestParameterException(MissingServletRequestParameterException ex) {
        log.warn("<- Res [400]: Missing ServletRequestParameter", ex);
        return new GeneralError()
                .message(ex.getMessage());
    }

    @ExceptionHandler({TokenKeeperException.class})
    @ResponseStatus(HttpStatus.UNAUTHORIZED)
    public void handleAccessDeniedException(TokenKeeperException ex) {
        log.warn("<- Res [401]: Request denied access", ex);
    }

    @ExceptionHandler({AuthorizationException.class})
    @ResponseStatus(HttpStatus.UNAUTHORIZED)
    public void handleAccessDeniedException(AuthorizationException ex) {
        log.warn("<- Res [401]: Request denied access", ex);
    }

    @ExceptionHandler(NotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public void handleNotFoundException(NotFoundException ex) {
        log.warn("<- Res [404]: Not found, type={}", ex.getType(), ex);
    }

    @ExceptionHandler({HttpMediaTypeNotAcceptableException.class})
    @ResponseStatus(HttpStatus.NOT_ACCEPTABLE)
    public void handleHttpMediaTypeNotAcceptable(HttpMediaTypeNotAcceptableException ex) {
        log.warn("<- Res [406]: MediaType not acceptable", ex);
    }

    @ExceptionHandler({HttpMediaTypeNotSupportedException.class})
    public ResponseEntity<?> handleHttpMediaTypeNotSupported(HttpMediaTypeNotSupportedException ex, WebRequest request) {
        log.warn("<- Res [415]: MediaType not supported", ex);
        return status(HttpStatus.UNSUPPORTED_MEDIA_TYPE)
                .headers(httpHeaders(ex))
                .build();
    }

    // ----------------- 5xx -----------------------------------------------------

    @ExceptionHandler(HttpClientErrorException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public void handleHttpClientErrorException(HttpClientErrorException ex) {
        log.error("<- Res [500]: Error with using inner http client, code={}, body={}",
                ex.getStatusCode(), ex.getResponseBodyAsString(), ex);
    }

    @ExceptionHandler(HttpTimeoutException.class)
    @ResponseStatus(HttpStatus.GATEWAY_TIMEOUT)
    public void handleHttpTimeoutException(HttpTimeoutException ex) {
        log.error("<- Res [504]: Timeout with using inner http client", ex);
    }

    @ExceptionHandler(Throwable.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public void handleException(Throwable ex) {
        log.error("<- Res [500]: Unrecognized inner error", ex);
    }

    private HttpHeaders httpHeaders(HttpMediaTypeNotSupportedException ex) {
        var headers = new HttpHeaders();
        var mediaTypes = ex.getSupportedMediaTypes();
        if (!CollectionUtils.isEmpty(mediaTypes)) {
            headers.setAccept(mediaTypes);
        }
        return headers;
    }
}


FILE: ./src/main/java/dev/vality/disputes/api/converter/DisputeConverter.java
MD5:  34275386e7deb095d724bbf837844899
SHA1: ecda88058a28ea56165719ca50344662dbd07e48
package dev.vality.disputes.api.converter;

import dev.vality.adapter.flow.lib.model.PollingInfo;
import dev.vality.disputes.api.model.PaymentParams;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.polling.ExponentialBackOffPollingServiceWrapper;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

@Component
@RequiredArgsConstructor
public class DisputeConverter {

    private final ExponentialBackOffPollingServiceWrapper exponentialBackOffPollingService;

    public Dispute convert(PaymentParams paymentParams, PollingInfo pollingInfo, Long amount, String reason) {
        var dispute = new Dispute();
        dispute.setCreatedAt(getLocalDateTime(pollingInfo.getStartDateTimePolling()));
        dispute.setNextCheckAfter(getNextCheckAfter(paymentParams, pollingInfo));
        dispute.setPollingBefore(getLocalDateTime(pollingInfo.getMaxDateTimePolling()));
        dispute.setInvoiceId(paymentParams.getInvoiceId());
        dispute.setPaymentId(paymentParams.getPaymentId());
        dispute.setProviderId(paymentParams.getProviderId());
        dispute.setTerminalId(paymentParams.getTerminalId());
        dispute.setProviderTrxId(paymentParams.getProviderTrxId());
        dispute.setAmount(amount == null ? paymentParams.getInvoiceAmount() : amount);
        dispute.setCurrencyName(paymentParams.getCurrencyName());
        dispute.setCurrencySymbolicCode(paymentParams.getCurrencySymbolicCode());
        dispute.setCurrencyNumericCode(paymentParams.getCurrencyNumericCode());
        dispute.setCurrencyExponent(paymentParams.getCurrencyExponent());
        dispute.setReason(reason);
        dispute.setShopId(paymentParams.getShopId());
        dispute.setShopDetailsName(paymentParams.getShopDetailsName());
        return dispute;
    }

    private LocalDateTime getNextCheckAfter(PaymentParams paymentParams, PollingInfo pollingInfo) {
        return exponentialBackOffPollingService.prepareNextPollingInterval(pollingInfo, paymentParams.getOptions());
    }

    private LocalDateTime getLocalDateTime(Instant instant) {
        return LocalDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}


FILE: ./src/main/java/dev/vality/disputes/api/converter/Status200ResponseConverter.java
MD5:  5bfbf20051735de70d1a4d1fbba7ea47
SHA1: 1641ddd93b1201d8982fd10901e91ec2486ceffe
package dev.vality.disputes.api.converter;

import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.swag.disputes.model.GeneralError;
import dev.vality.swag.disputes.model.Status200Response;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Component;

@Component
@SuppressWarnings({"LineLength"})
public class Status200ResponseConverter {

    public Status200Response convert(Dispute dispute) {
        var body = new Status200Response();
        var status = getStatus(dispute);
        body.setStatus(status);
        if (status == Status200Response.StatusEnum.FAILED && !StringUtils.isBlank(dispute.getMapping())) {
            body.setReason(new GeneralError(dispute.getMapping()));
        }
        if (status == Status200Response.StatusEnum.SUCCEEDED && dispute.getChangedAmount() != null) {
            body.setChangedAmount(dispute.getChangedAmount());
        }
        return body;
    }

    private Status200Response.StatusEnum getStatus(Dispute dispute) {
        return switch (dispute.getStatus()) {
            case already_exist_created, manual_pending, create_adjustment, pooling_expired,
                 created, pending -> Status200Response.StatusEnum.PENDING;
            case succeeded -> Status200Response.StatusEnum.SUCCEEDED;
            case cancelled, failed -> Status200Response.StatusEnum.FAILED;
            default -> throw new NotFoundException(
                    String.format("Dispute not found, disputeId='%s'", dispute.getId()), NotFoundException.Type.DISPUTE);
        };
    }
}


FILE: ./src/main/java/dev/vality/disputes/api/model/PaymentParams.java
MD5:  e8bf8a87ed4533fdb9033a78243e06a5
SHA1: 0c2c78fa1cb66d748d19e45afc9051d44ff39c3f
package dev.vality.disputes.api.model;

import lombok.Builder;
import lombok.Data;
import lombok.ToString;

import java.util.Map;

@Builder
@Data
public class PaymentParams {

    private String invoiceId;
    private String paymentId;
    private Integer terminalId;
    private Integer providerId;
    private String providerTrxId;
    private String currencyName;
    private String currencySymbolicCode;
    private Integer currencyNumericCode;
    private Integer currencyExponent;
    @ToString.Exclude
    private Map<String, String> options;
    private String shopId;
    private String shopDetailsName;
    private Long invoiceAmount;

}


FILE: ./src/main/java/dev/vality/disputes/api/service/ApiAttachmentsService.java
MD5:  efe45dfe98ec48d351994a1f052c869b
SHA1: 2eefba0ae0eee251640e6d6f946069bac96c0c7e
package dev.vality.disputes.api.service;

import dev.vality.disputes.dao.FileMetaDao;
import dev.vality.disputes.domain.tables.pojos.FileMeta;
import dev.vality.disputes.service.external.FileStorageService;
import dev.vality.swag.disputes.model.CreateRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
@SuppressWarnings({"LineLength"})
public class ApiAttachmentsService {

    private final FileMetaDao fileMetaDao;
    private final FileStorageService fileStorageService;

    public void createAttachments(CreateRequest req, UUID disputeId) {
        log.debug("Trying to save Attachments {}", disputeId);
        for (var attachment : req.getAttachments()) {
            // validate
            MediaType.valueOf(attachment.getMimeType());
            var fileId = fileStorageService.saveFile(attachment.getData());
            var fileMeta = new FileMeta(fileId, disputeId, attachment.getMimeType());
            fileMetaDao.save(fileMeta);
        }
        log.debug("Attachments have been saved {}", disputeId);
    }
}


FILE: ./src/main/java/dev/vality/disputes/api/service/ApiDisputesService.java
MD5:  7111926a8d84ebc889caa856086f337a
SHA1: 3c140849f2df7a548f928922892a0f956860041c
package dev.vality.disputes.api.service;

import dev.vality.disputes.api.converter.DisputeConverter;
import dev.vality.disputes.api.model.PaymentParams;
import dev.vality.disputes.constant.ErrorMessage;
import dev.vality.disputes.dao.DisputeDao;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.polling.PollingInfoService;
import dev.vality.swag.disputes.model.CreateRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;
import java.util.UUID;

import static dev.vality.disputes.exception.NotFoundException.Type;
import static dev.vality.disputes.service.DisputesService.DISPUTE_PENDING_STATUSES;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ApiDisputesService {

    private final DisputeDao disputeDao;
    private final DisputeConverter disputeConverter;
    private final ApiAttachmentsService apiAttachmentsService;
    private final ApiNotificationService apiNotificationService;
    private final PollingInfoService pollingInfoService;

    public Optional<Dispute> checkExistBeforeCreate(String invoiceId, String paymentId) {
        log.debug("Trying to checkExistBeforeCreate() Dispute, invoiceId={}", invoiceId);
        try {
            return Optional.of(disputeDao.getByInvoiceId(invoiceId, paymentId))
                    .filter(dispute -> DISPUTE_PENDING_STATUSES.contains(dispute.getStatus()));
        } catch (NotFoundException ex) {
            return Optional.empty();
        }
    }

    @Transactional
    public UUID createDispute(CreateRequest req, PaymentParams paymentParams) {
        log.info("Start creating Dispute {}", paymentParams);
        var pollingInfo = pollingInfoService.initPollingInfo(paymentParams.getOptions());
        var dispute = disputeConverter.convert(paymentParams, pollingInfo, req.getAmount(), req.getReason());
        var disputeId = disputeDao.save(dispute);
        apiAttachmentsService.createAttachments(req, disputeId);
        apiNotificationService.saveNotification(req, paymentParams, pollingInfo, disputeId);
        log.debug("Finish creating Dispute {}", dispute);
        return disputeId;
    }

    public Dispute getDispute(String disputeId) {
        log.debug("Trying to get Dispute, disputeId={}", disputeId);
        var dispute = Optional.ofNullable(parseFormat(disputeId))
                .map(disputeDao::get)
                .filter(d -> !(ErrorMessage.NO_ATTACHMENTS.equals(d.getErrorMessage())
                        || ErrorMessage.INVOICE_NOT_FOUND.equals(d.getErrorMessage())
                        || ErrorMessage.PAYMENT_NOT_FOUND.equals(d.getErrorMessage())
                        || getSafeErrorMessage(d).contains(ErrorMessage.PAYMENT_STATUS_RESTRICTIONS)))
                .orElseThrow(() -> new NotFoundException(
                        String.format("Dispute not found, disputeId='%s'", disputeId), Type.DISPUTE));
        log.debug("Dispute has been found, disputeId={}", disputeId);
        return dispute;
    }

    private UUID parseFormat(String disputeId) {
        try {
            return UUID.fromString(disputeId);
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }

    private String getSafeErrorMessage(Dispute d) {
        return d.getErrorMessage() == null ? "" : d.getErrorMessage();
    }
}


FILE: ./src/main/java/dev/vality/disputes/api/service/ApiNotificationService.java
MD5:  10d4fa98684f2cd6417384870a27cce6
SHA1: 78fd6bcb33c63acac66c0ce8529164d7343a5ce5
package dev.vality.disputes.api.service;

import dev.vality.adapter.flow.lib.model.PollingInfo;
import dev.vality.disputes.api.model.PaymentParams;
import dev.vality.disputes.dao.NotificationDao;
import dev.vality.disputes.domain.tables.pojos.Notification;
import dev.vality.disputes.polling.ExponentialBackOffPollingServiceWrapper;
import dev.vality.swag.disputes.model.CreateRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
@SuppressWarnings({"LineLength"})
public class ApiNotificationService {

    private final NotificationDao notificationDao;
    private final ExponentialBackOffPollingServiceWrapper exponentialBackOffPollingService;

    @Value("${dispute.notificationsMaxAttempts}")
    private int notificationsMaxAttempts;

    public void saveNotification(CreateRequest req, PaymentParams paymentParams, PollingInfo pollingInfo, UUID disputeId) {
        if (req.getNotificationUrl() != null) {
            log.debug("Trying to save Notification {}", disputeId);
            var notification = new Notification();
            notification.setDisputeId(disputeId);
            notification.setNotificationUrl(req.getNotificationUrl());
            notification.setNextAttemptAfter(getNextAttemptAfter(paymentParams, pollingInfo));
            notification.setMaxAttempts(notificationsMaxAttempts);
            notificationDao.save(notification);
            log.debug("Notification has been saved {}", disputeId);
        }
    }

    private LocalDateTime getNextAttemptAfter(PaymentParams paymentParams, PollingInfo pollingInfo) {
        return exponentialBackOffPollingService.prepareNextPollingInterval(pollingInfo, paymentParams.getOptions());
    }
}


FILE: ./src/main/java/dev/vality/disputes/api/service/PaymentParamsBuilder.java
MD5:  5db90e04acfeee1c099485bc2d135ad9
SHA1: 0ecccd93a6f47b108690756740a25fa0e27911b8
package dev.vality.disputes.api.service;

import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.damsel.payment_processing.InvoicePayment;
import dev.vality.disputes.api.model.PaymentParams;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.schedule.service.ProviderDataService;
import dev.vality.disputes.security.AccessData;
import dev.vality.disputes.service.external.PartyManagementService;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.Optional;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class PaymentParamsBuilder {

    private final ProviderDataService providerDataService;
    private final PartyManagementService partyManagementService;

    @SneakyThrows
    public PaymentParams buildGeneralPaymentContext(AccessData accessData) {
        var invoice = accessData.getInvoice().getInvoice();
        log.debug("Start building PaymentParams id={}", invoice.getId());
        var payment = accessData.getPayment();
        var currency = providerDataService.getAsyncCurrency(payment);
        var shop = partyManagementService.getShop(invoice.getOwnerId(), invoice.getShopId());
        var paymentParams = PaymentParams.builder()
                .invoiceId(invoice.getId())
                .paymentId(payment.getPayment().getId())
                .terminalId(payment.getRoute().getTerminal().getId())
                .providerId(payment.getRoute().getProvider().getId())
                .providerTrxId(getProviderTrxId(payment))
                .currencyName(currency.getName())
                .currencySymbolicCode(currency.getSymbolicCode())
                .currencyNumericCode((int) currency.getNumericCode())
                .currencyExponent((int) currency.getExponent())
                .options(providerDataService.getAsyncProviderData(payment).getOptions())
                .shopId(invoice.getShopId())
                .shopDetailsName(shop.getDetails().getName())
                .invoiceAmount(payment.getPayment().getCost().getAmount())
                .build();
        log.debug("Finish building PaymentParams {}", paymentParams);
        return paymentParams;
    }

    private String getProviderTrxId(InvoicePayment payment) {
        return Optional.ofNullable(payment.getLastTransactionInfo())
                .map(TransactionInfo::getId)
                .orElseThrow(() -> new NotFoundException(
                        String.format("Payment with id: %s and filled ProviderTrxId not found!", payment.getPayment().getId()), NotFoundException.Type.PROVIDERTRXID));
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/AccessConfig.java
MD5:  7452e730d889376d20a932c332ae8313
SHA1: 3d439d36613b6ce9fb20195e29c3c58b22f5e2d9
package dev.vality.disputes.config;

import dev.vality.bouncer.decisions.ArbiterSrv;
import dev.vality.token.keeper.TokenAuthenticatorSrv;
import dev.vality.woody.thrift.impl.http.THSpawnClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;

import java.io.IOException;

@Configuration
public class AccessConfig {

    @Bean
    public ArbiterSrv.Iface bouncerClient(
            @Value("${service.bouncer.url}") Resource resource,
            @Value("${service.bouncer.networkTimeout}") int networkTimeout) throws IOException {
        return new THSpawnClientBuilder()
                .withNetworkTimeout(networkTimeout)
                .withAddress(resource.getURI())
                .build(ArbiterSrv.Iface.class);
    }

    @Bean
    public TokenAuthenticatorSrv.Iface tokenKeeperClient(
            @Value("${service.tokenKeeper.url}") Resource resource,
            @Value("${service.tokenKeeper.networkTimeout}") int networkTimeout) throws IOException {
        return new THSpawnClientBuilder()
                .withNetworkTimeout(networkTimeout)
                .withAddress(resource.getURI())
                .build(TokenAuthenticatorSrv.Iface.class);
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/ApplicationConfig.java
MD5:  54daba6d3794c294f19e46410741ec93
SHA1: db34953d2fff7bede6f2ddc55a0134e7e180d139
package dev.vality.disputes.config;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jdk8.Jdk8Module;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.google.common.util.concurrent.ThreadFactoryBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@Configuration
public class ApplicationConfig {

    @Bean
    public ExecutorService disputesThreadPool(@Value("${dispute.batchSize}") int threadPoolSize) {
        final var threadFactory = new ThreadFactoryBuilder()
                .setNameFormat("dispute-exec-%d")
                .setDaemon(true)
                .build();
        return Executors.newFixedThreadPool(threadPoolSize, threadFactory);
    }

    @Bean
    public ExecutorService providerPaymentsThreadPool(@Value("${provider.payments.batchSize}") int threadPoolSize) {
        final var threadFactory = new ThreadFactoryBuilder()
                .setNameFormat("provider-payments-exec-%d")
                .setDaemon(true)
                .build();
        return Executors.newFixedThreadPool(threadPoolSize, threadFactory);
    }

    @Bean
    @Primary
    public ObjectMapper customObjectMapper() {
        return new ObjectMapper()
                .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
                .configure(JsonParser.Feature.ALLOW_SINGLE_QUOTES, true)
                .registerModule(new JavaTimeModule())
                .registerModule(new Jdk8Module())
                .setSerializationInclusion(JsonInclude.Include.NON_NULL);
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/AsyncMdcConfiguration.java
MD5:  41e1f849470863b533d4c17919cdc67d
SHA1: 2152de5bf9267484da528db56ce508c8a0936a84
package dev.vality.disputes.config;

import dev.vality.disputes.config.properties.AsyncProperties;
import dev.vality.disputes.service.MdcTaskDecorator;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.util.concurrent.Executor;

@Configuration
@RequiredArgsConstructor
public class AsyncMdcConfiguration {

    private final AsyncProperties asyncProperties;

    @Bean("disputesAsyncServiceExecutor")
    public Executor disputesAsyncServiceExecutor() {
        var executor = new ThreadPoolTaskExecutor();
        executor.setTaskDecorator(new MdcTaskDecorator());
        executor.initialize();
        executor.setThreadNamePrefix("disputesAsyncService-thread-");
        executor.setCorePoolSize(asyncProperties.getCorePoolSize());
        executor.setMaxPoolSize(asyncProperties.getMaxPoolSize());
        executor.setQueueCapacity(asyncProperties.getQueueCapacity());
        executor.initialize();
        return executor;
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/CacheConfig.java
MD5:  f0e72848128295832cdd48fbfc7d3882
SHA1: d4cdad1c49f6bafe9896e01b21216e4f010750b2
package dev.vality.disputes.config;

import com.github.benmanes.caffeine.cache.Caffeine;
import dev.vality.disputes.config.properties.AdaptersConnectionProperties;
import dev.vality.disputes.config.properties.DominantCacheProperties;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.caffeine.CaffeineCacheManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

import java.util.List;
import java.util.concurrent.TimeUnit;

@Configuration
@EnableCaching
@RequiredArgsConstructor
public class CacheConfig {

    private final AdaptersConnectionProperties adaptersConnectionProperties;
    private final DominantCacheProperties dominantCacheProperties;

    @Bean
    @Primary
    public CacheManager providerDisputesCacheManager() {
        var caffeineCacheManager = new CaffeineCacheManager();
        caffeineCacheManager.setCaffeine(adaptersConnectionsCacheConfig());
        caffeineCacheManager.setCacheNames(List.of("providerDisputes"));
        return caffeineCacheManager;
    }

    @Bean
    public CacheManager providerPaymentsCacheManager() {
        var caffeineCacheManager = new CaffeineCacheManager();
        caffeineCacheManager.setCaffeine(adaptersConnectionsCacheConfig());
        caffeineCacheManager.setCacheNames(List.of("providerPayments"));
        return caffeineCacheManager;
    }

    @Bean
    public CacheManager currenciesCacheManager() {
        var caffeineCacheManager = new CaffeineCacheManager();
        caffeineCacheManager.setCaffeine(getCacheConfig(dominantCacheProperties.getCurrencies()));
        caffeineCacheManager.setCacheNames(List.of("currencies"));
        return caffeineCacheManager;
    }

    @Bean
    public CacheManager terminalsCacheManager() {
        var caffeineCacheManager = new CaffeineCacheManager();
        caffeineCacheManager.setCaffeine(getCacheConfig(dominantCacheProperties.getTerminals()));
        caffeineCacheManager.setCacheNames(List.of("terminals"));
        return caffeineCacheManager;
    }

    @Bean
    public CacheManager providersCacheManager() {
        var caffeineCacheManager = new CaffeineCacheManager();
        caffeineCacheManager.setCaffeine(getCacheConfig(dominantCacheProperties.getProviders()));
        caffeineCacheManager.setCacheNames(List.of("providers"));
        return caffeineCacheManager;
    }

    @Bean
    public CacheManager proxiesCacheManager() {
        var caffeineCacheManager = new CaffeineCacheManager();
        caffeineCacheManager.setCaffeine(getCacheConfig(dominantCacheProperties.getProxies()));
        caffeineCacheManager.setCacheNames(List.of("proxies"));
        return caffeineCacheManager;
    }

    private Caffeine<Object, Object> adaptersConnectionsCacheConfig() {
        return Caffeine.newBuilder()
                .expireAfterAccess(adaptersConnectionProperties.getTtlMin(), TimeUnit.MINUTES)
                .maximumSize(adaptersConnectionProperties.getPoolSize());
    }

    private Caffeine<Object, Object> getCacheConfig(DominantCacheProperties.CacheConfig cacheConfig) {
        return Caffeine.newBuilder()
                .expireAfterAccess(cacheConfig.getTtlSec(), TimeUnit.SECONDS)
                .maximumSize(cacheConfig.getPoolSize());
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/DominantConfig.java
MD5:  c72581f46d45087c25c648a965646b4a
SHA1: 3172883e2ffb208b6412fed92c7cdadf06c7343d
package dev.vality.disputes.config;

import dev.vality.damsel.domain_config.RepositoryClientSrv;
import dev.vality.woody.thrift.impl.http.THSpawnClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;

import java.io.IOException;

@Configuration
public class DominantConfig {

    @Bean
    public RepositoryClientSrv.Iface dominantClient(
            @Value("${service.dominant.url}") Resource resource,
            @Value("${service.dominant.networkTimeout}") int networkTimeout) throws IOException {
        return new THSpawnClientBuilder()
                .withNetworkTimeout(networkTimeout)
                .withAddress(resource.getURI())
                .build(RepositoryClientSrv.Iface.class);
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/FileStorageConfig.java
MD5:  68d3a383fb0cf7c904a4c680e15dd584
SHA1: 1dfa830ad78b8330b4446fa63b36b0a554938050
package dev.vality.disputes.config;

import dev.vality.file.storage.FileStorageSrv;
import dev.vality.woody.thrift.impl.http.THSpawnClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;

import java.io.IOException;

@Configuration
public class FileStorageConfig {

    @Bean
    public FileStorageSrv.Iface fileStorageClient(
            @Value("${service.file-storage.url}") Resource resource,
            @Value("${service.file-storage.networkTimeout}") int networkTimeout) throws IOException {
        return new THSpawnClientBuilder()
                .withNetworkTimeout(networkTimeout)
                .withAddress(resource.getURI())
                .build(FileStorageSrv.Iface.class);
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/HellgateConfig.java
MD5:  62cea8ae2262952d6b9d5a4313bfd8bd
SHA1: 24b644bf60ee95596511a6e02330cf5cbe11719f
package dev.vality.disputes.config;

import dev.vality.damsel.payment_processing.InvoicingSrv;
import dev.vality.woody.thrift.impl.http.THSpawnClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;

import java.io.IOException;

@Configuration
public class HellgateConfig {

    @Bean
    public InvoicingSrv.Iface invoicingClient(
            @Value("${service.invoicing.url}") Resource resource,
            @Value("${service.invoicing.networkTimeout}") int networkTimeout) throws IOException {
        return new THSpawnClientBuilder()
                .withAddress(resource.getURI())
                .withNetworkTimeout(networkTimeout)
                .build(InvoicingSrv.Iface.class);
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/HttpClientConfig.java
MD5:  ff7d185530ad982a61654f05f7708fcc
SHA1: d01a6f2b6948902a0f5965fc522ee3c97718dfca
package dev.vality.disputes.config;

import dev.vality.disputes.config.properties.HttpClientProperties;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.config.RequestConfig;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.client5.http.ssl.DefaultClientTlsStrategy;
import org.apache.hc.client5.http.ssl.HostnameVerificationPolicy;
import org.apache.hc.client5.http.ssl.NoopHostnameVerifier;
import org.apache.hc.client5.http.ssl.TrustAllStrategy;
import org.apache.hc.core5.ssl.SSLContextBuilder;
import org.apache.hc.core5.util.Timeout;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@RequiredArgsConstructor
public class HttpClientConfig {

    private final HttpClientProperties httpClientProperties;

    @Bean
    public PoolingHttpClientConnectionManager poolingHttpClientConnectionManager() {
        return PoolingHttpClientConnectionManagerBuilder.create()
                .setTlsSocketStrategy(defaultClientTlsStrategy())
                .setMaxConnTotal(httpClientProperties.getMaxTotalPooling())
                .setMaxConnPerRoute(httpClientProperties.getDefaultMaxPerRoute())
                .setDefaultConnectionConfig(connectionConfig()).build();
    }

    private ConnectionConfig connectionConfig() {
        return ConnectionConfig.custom()
                .setConnectTimeout(Timeout.ofMilliseconds(httpClientProperties.getConnectionTimeout()))
                .setSocketTimeout(Timeout.ofMilliseconds(httpClientProperties.getRequestTimeout()))
                .build();
    }

    @Bean
    public RequestConfig requestConfig() {
        return RequestConfig.custom()
                .setConnectionRequestTimeout(Timeout.ofMilliseconds(httpClientProperties.getPoolTimeout()))
                .build();
    }

    @Bean
    public CloseableHttpClient httpClient(
            PoolingHttpClientConnectionManager manager,
            RequestConfig requestConfig) {
        return HttpClients.custom()
                .setConnectionManager(manager)
                .setDefaultRequestConfig(requestConfig)
                .disableAutomaticRetries()
                .setConnectionManagerShared(true)
                .build();
    }

    @SneakyThrows
    private DefaultClientTlsStrategy defaultClientTlsStrategy() {
        var sslContext = new SSLContextBuilder().loadTrustMaterial(null, new TrustAllStrategy()).build();
        return new DefaultClientTlsStrategy(
                sslContext,
                HostnameVerificationPolicy.CLIENT,
                NoopHostnameVerifier.INSTANCE);
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/NetworkConfig.java
MD5:  a15542b4326fb9b452ee16b942db274d
SHA1: acb4dd3f8774766f8f5a120d9de2ffbbf91c1f33
package dev.vality.disputes.config;

import dev.vality.woody.api.flow.WFlow;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.SneakyThrows;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Configuration
@SuppressWarnings({"LineLength"})
public class NetworkConfig {

    @Value("${server.port}")
    private int restPort;

    @Value("${openapi.valityDisputes.base-path:/disputes}/")
    private String restEndpoint;

    public static final String HEALTH = "/actuator/health";
    public static final String MERCHANT = "/v1/merchant";
    public static final String ADMIN_MANAGEMENT = "/v1/admin-management";
    public static final String CALLBACK = "/v1/callback";

    @Bean
    public FilterRegistrationBean<OncePerRequestFilter> externalPortRestrictingFilter() {
        var filter = new OncePerRequestFilter() {

            @Override
            protected void doFilterInternal(HttpServletRequest request,
                                            HttpServletResponse response,
                                            FilterChain filterChain) throws ServletException, IOException {
                var servletPath = request.getServletPath();
                var enabledPaths = servletPath.startsWith(restEndpoint)
                        || servletPath.startsWith(HEALTH)
                        || servletPath.startsWith(MERCHANT)
                        || servletPath.startsWith(ADMIN_MANAGEMENT)
                        || servletPath.startsWith(CALLBACK);
                if ((request.getLocalPort() == restPort) && !enabledPaths) {
                    response.sendError(404, "Unknown address");
                    return;
                }
                filterChain.doFilter(request, response);
            }
        };
        var filterRegistrationBean = new FilterRegistrationBean<OncePerRequestFilter>();
        filterRegistrationBean.setFilter(filter);
        filterRegistrationBean.setOrder(-100);
        filterRegistrationBean.setName("httpPortFilter");
        filterRegistrationBean.addUrlPatterns("/*");
        return filterRegistrationBean;
    }

    @Bean
    public FilterRegistrationBean<OncePerRequestFilter> woodyFilter() {
        var woodyFlow = new WFlow();
        var filter = new OncePerRequestFilter() {

            @Override
            protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) {
                if ((request.getLocalPort() == restPort)
                        && request.getServletPath().startsWith(restEndpoint)) {
                    woodyFlow.createServiceFork(() -> doFilter(request, response, filterChain)).run();
                    return;
                }
                doFilter(request, response, filterChain);
            }

            @SneakyThrows
            private void doFilter(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) {
                filterChain.doFilter(request, response);
            }
        };
        var filterRegistrationBean = new FilterRegistrationBean<OncePerRequestFilter>();
        filterRegistrationBean.setFilter(filter);
        filterRegistrationBean.setOrder(-50);
        filterRegistrationBean.setName("woodyFilter");
        filterRegistrationBean.addUrlPatterns(restEndpoint + "*");
        return filterRegistrationBean;
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/OtelConfig.java
MD5:  bd2a7ee2898e3ee06af9aa48d2ea0473
SHA1: fa2daa0e24291b92fd33b5228c9a1c8b5e6d90ca
package dev.vality.disputes.config;

import dev.vality.disputes.config.properties.OtelProperties;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.propagation.ContextPropagators;
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import io.opentelemetry.sdk.trace.samplers.Sampler;
import io.opentelemetry.semconv.resource.attributes.ResourceAttributes;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

@Slf4j
@Configuration
@ConditionalOnProperty(value = "otel.enabled", havingValue = "true", matchIfMissing = true)
@RequiredArgsConstructor
public class OtelConfig {

    private final OtelProperties otelProperties;

    @Value("${spring.application.name}")
    private String applicationName;

    @Bean
    public OpenTelemetry openTelemetryConfig() {
        var resource = Resource.getDefault()
                .merge(Resource.create(Attributes.of(ResourceAttributes.SERVICE_NAME, applicationName)));
        var sdkTracerProvider = SdkTracerProvider.builder()
                .addSpanProcessor(BatchSpanProcessor.builder(OtlpHttpSpanExporter.builder()
                                .setEndpoint(otelProperties.getResource())
                                .setTimeout(Duration.ofMillis(otelProperties.getTimeout()))
                                .build())
                        .build())
                .setSampler(Sampler.alwaysOn())
                .setResource(resource)
                .build();
        var openTelemetrySdk = OpenTelemetrySdk.builder()
                .setTracerProvider(sdkTracerProvider)
                .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
                .build();
        registerGlobalOpenTelemetry(openTelemetrySdk);
        return openTelemetrySdk;
    }

    private static void registerGlobalOpenTelemetry(OpenTelemetry openTelemetry) {
        try {
            GlobalOpenTelemetry.set(openTelemetry);
        } catch (Throwable ex) {
            log.warn("Please initialize the ObservabilitySdk before starting the application", ex);
            GlobalOpenTelemetry.resetForTest();
            try {
                GlobalOpenTelemetry.set(openTelemetry);
            } catch (Throwable ex1) {
                log.warn("Unable to set GlobalOpenTelemetry", ex1);
            }
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/PartyManagementConfig.java
MD5:  333cb2cf6601643968fa1cd109273084
SHA1: 15748b1f9580e5a4c5abc59646af70acadc1eaa5
package dev.vality.disputes.config;

import dev.vality.damsel.payment_processing.PartyManagementSrv;
import dev.vality.woody.thrift.impl.http.THSpawnClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;

import java.io.IOException;

@Configuration
public class PartyManagementConfig {

    @Bean
    public PartyManagementSrv.Iface partyManagementClient(
            @Value("${service.party-management.url}") Resource resource,
            @Value("${service.party-management.networkTimeout}") int timeout) throws IOException {
        return new THSpawnClientBuilder()
                .withAddress(resource.getURI())
                .withNetworkTimeout(timeout)
                .build(PartyManagementSrv.Iface.class);
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/TgBotConfig.java
MD5:  75b2aea69e9c25adbdf767c922b54e01
SHA1: b8bd2f8c8a2167f5dcc3e2cd8719b3067e62394b
package dev.vality.disputes.config;

import dev.vality.disputes.admin.AdminCallbackServiceSrv;
import dev.vality.disputes.provider.ProviderDisputesServiceSrv;
import dev.vality.woody.thrift.impl.http.THSpawnClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;

import java.io.IOException;

@Configuration
public class TgBotConfig {

    @Bean
    public ProviderDisputesServiceSrv.Iface providerDisputesTgBotClient(
            @Value("${service.disputes-tg-bot.provider.url}") Resource resource,
            @Value("${service.disputes-tg-bot.provider.networkTimeout}") int networkTimeout) throws IOException {
        return new THSpawnClientBuilder()
                .withNetworkTimeout(networkTimeout)
                .withAddress(resource.getURI())
                .build(ProviderDisputesServiceSrv.Iface.class);
    }

    @Bean
    public AdminCallbackServiceSrv.Iface adminCallbackDisputesTgBotClient(
            @Value("${service.disputes-tg-bot.admin.url}") Resource resource,
            @Value("${service.disputes-tg-bot.admin.networkTimeout}") int networkTimeout) throws IOException {
        return new THSpawnClientBuilder()
                .withNetworkTimeout(networkTimeout)
                .withAddress(resource.getURI())
                .build(AdminCallbackServiceSrv.Iface.class);
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/properties/AdaptersConnectionProperties.java
MD5:  a0d29f5dabcef05aff9cba8ede324485
SHA1: d05c034416111ab4da57d5f7b4b89495b3912c70
package dev.vality.disputes.config.properties;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Getter
@Setter
@Component
@ConfigurationProperties(prefix = "service.adapters.connection")
public class AdaptersConnectionProperties {

    private Integer timeoutSec = 30;
    private Integer poolSize = 10;
    private Integer ttlMin = 1440;
    private ReconnectProperties reconnect;

    @Getter
    @Setter
    public static class ReconnectProperties {
        private int maxAttempts;
        private int initialDelaySec;
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/properties/AsyncProperties.java
MD5:  b784acd63f9ccf5950719e83e544feff
SHA1: 0d6a86baa997a5a0f67ceb6e2611cad52b9e1e1b
package dev.vality.disputes.config.properties;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.validation.annotation.Validated;

import javax.validation.constraints.NotNull;

@Configuration
@ConfigurationProperties(prefix = "async")
@Validated
@Getter
@Setter
public class AsyncProperties {

    @NotNull
    private Integer corePoolSize;
    @NotNull
    private Integer maxPoolSize;
    @NotNull
    private Integer queueCapacity;
}


FILE: ./src/main/java/dev/vality/disputes/config/properties/BouncerProperties.java
MD5:  5488442ae648291a028be9ac608dd0a8
SHA1: 3da364b4e07ec1f61f09f7df5b7ea16b61ba17c1
package dev.vality.disputes.config.properties;

import jakarta.validation.constraints.NotEmpty;
import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

@Getter
@Setter
@Component
@Validated
@ConfigurationProperties(prefix = "service.bouncer")
public class BouncerProperties {

    @NotEmpty
    private String deploymentId;
    @NotEmpty
    private String ruleSetId;
    @NotEmpty
    private String operationId;

}


FILE: ./src/main/java/dev/vality/disputes/config/properties/DisputesTimerProperties.java
MD5:  7331aa845992517a8cee1aee92597afb
SHA1: bf7e80775efcd69655cfd04688efcc2b222b8243
package dev.vality.disputes.config.properties;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.validation.annotation.Validated;

import javax.validation.constraints.NotNull;

@Getter
@Setter
@Validated
@Configuration
@ConfigurationProperties("time.config")
public class DisputesTimerProperties {

    @NotNull
    private int maxTimePollingMin;

}


FILE: ./src/main/java/dev/vality/disputes/config/properties/DominantCacheProperties.java
MD5:  3b1a99b2f581c6023d83ffaba60a27d8
SHA1: fe2c438ba52b35c11f3afc4b8be9ff729e0a94e1
package dev.vality.disputes.config.properties;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

@Getter
@Setter
@Component
@Validated
@ConfigurationProperties(prefix = "service.dominant.cache")
public class DominantCacheProperties {

    private CacheConfig currencies;
    private CacheConfig terminals;
    private CacheConfig providers;
    private CacheConfig paymentServices;
    private CacheConfig proxies;


    @Getter
    @Setter
    public static class CacheConfig {
        private int poolSize;
        private int ttlSec;
    }
}


FILE: ./src/main/java/dev/vality/disputes/config/properties/FileStorageProperties.java
MD5:  e0547799675fb89c81d390f0dfa50b52
SHA1: 287bf0c3be7db2e03f7d7b5240fed4bfe486511d
package dev.vality.disputes.config.properties;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

import java.time.ZoneId;

@Getter
@Setter
@Component
@Validated
@ConfigurationProperties(prefix = "service.file-storage")
public class FileStorageProperties {

    private Resource url;
    private int clientTimeout;
    private Long urlLifeTimeDuration;
    private ZoneId timeZone;

}


FILE: ./src/main/java/dev/vality/disputes/config/properties/HttpClientProperties.java
MD5:  8234203a588fbf5af6af761a4f9d9c53
SHA1: 242c6bd3caa1335f1a8bfd633c42b22d2dfae052
package dev.vality.disputes.config.properties;

import jakarta.validation.constraints.NotNull;
import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.validation.annotation.Validated;

@Getter
@Setter
@Validated
@Configuration
@ConfigurationProperties("http-client")
public class HttpClientProperties {

    @NotNull
    private int maxTotalPooling;
    @NotNull
    private int defaultMaxPerRoute;
    @NotNull
    private int requestTimeout;
    @NotNull
    private int poolTimeout;
    @NotNull
    private int connectionTimeout;

}


FILE: ./src/main/java/dev/vality/disputes/config/properties/OtelProperties.java
MD5:  39d5b97350e8aa79902decf45cd4c3f6
SHA1: 8646dfb073256693cb8d585c4294b4bb87ff8c72
package dev.vality.disputes.config.properties;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Getter
@Setter
@Component
@ConfigurationProperties(prefix = "otel")
public class OtelProperties {

    private String resource;
    private Long timeout;

}


FILE: ./src/main/java/dev/vality/disputes/constant/ErrorMessage.java
MD5:  e10f05560d67228590b2f8d7494cf885
SHA1: 0aedd3a15509d79d437488186919ba2a04569210
package dev.vality.disputes.constant;

public class ErrorMessage {

    public static final String NO_ATTACHMENTS = "no attachments";
    public static final String INVOICE_NOT_FOUND = "invoice not found";
    public static final String PAYMENT_NOT_FOUND = "payment not found";
    public static final String POOLING_EXPIRED = "pooling expired";
    public static final String PAYMENT_STATUS_RESTRICTIONS = "payment status restrictions";
    public static final String AUTO_FAIL_BY_CREATE_ADJUSTMENT_CALL = "auto fail by CreateAdjustment call";
    public static final String NEXT_STEP_AFTER_DEFAULT_REMOTE_CLIENT_CALL = "next step after defaultRemoteClient call";

}


FILE: ./src/main/java/dev/vality/disputes/constant/ModerationPrefix.java
MD5:  d5051ed133d8e394633e3edc5ef7cad3
SHA1: 64b09ad8cd9dcd2cddeffc7116ddba7eccc57e4a
package dev.vality.disputes.constant;

public class ModerationPrefix {

    public static final String DISPUTES_UNKNOWN_MAPPING = "disputes_unknown_mapping";

}


FILE: ./src/main/java/dev/vality/disputes/constant/TerminalOptionsField.java
MD5:  51c878d9214ad3efcf0e1ea696ebbba3
SHA1: 8c929b584fa70be0582d3f223194a834ed7b9190
package dev.vality.disputes.constant;

import lombok.NoArgsConstructor;

@NoArgsConstructor
public class TerminalOptionsField {

    public static final String DISPUTE_FLOW_MAX_TIME_POLLING_MIN = "DISPUTE_FLOW_MAX_TIME_POLLING_MIN";
    public static final String DISPUTE_FLOW_PROVIDERS_API_EXIST = "DISPUTE_FLOW_PROVIDERS_API_EXIST";

}


FILE: ./src/main/java/dev/vality/disputes/dao/DisputeDao.java
MD5:  012409d4c82e3bdcf0543442d7d85931
SHA1: f0d9c54446aac8ec661487a6c885c4a2aceaa7f5
package dev.vality.disputes.dao;

import dev.vality.dao.impl.AbstractGenericDao;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.mapper.RecordRowMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static dev.vality.disputes.domain.tables.Dispute.DISPUTE;

@Component
@SuppressWarnings({"LineLength"})
public class DisputeDao extends AbstractGenericDao {

    private final RowMapper<Dispute> disputeRowMapper;

    @Autowired
    public DisputeDao(DataSource dataSource) {
        super(dataSource);
        disputeRowMapper = new RecordRowMapper<>(DISPUTE, Dispute.class);
    }

    public UUID save(Dispute dispute) {
        var record = getDslContext().newRecord(DISPUTE, dispute);
        var query = getDslContext().insertInto(DISPUTE)
                .set(record)
                .returning(DISPUTE.ID);
        var keyHolder = new GeneratedKeyHolder();
        execute(query, keyHolder);
        return Optional.ofNullable(keyHolder.getKeyAs(UUID.class)).orElseThrow();
    }

    public Dispute get(UUID disputeId) {
        var query = getDslContext().selectFrom(DISPUTE)
                .where(DISPUTE.ID.eq(disputeId));
        return Optional.ofNullable(fetchOne(query, disputeRowMapper))
                .orElseThrow(() -> new NotFoundException(
                        String.format("Dispute not found, disputeId='%s'", disputeId), NotFoundException.Type.DISPUTE));
    }

    public Dispute getSkipLocked(UUID disputeId) {
        var query = getDslContext().selectFrom(DISPUTE)
                .where(DISPUTE.ID.eq(disputeId))
                .forUpdate()
                .skipLocked();
        return Optional.ofNullable(fetchOne(query, disputeRowMapper))
                .orElseThrow(() -> new NotFoundException(
                        String.format("Dispute not found, disputeId='%s'", disputeId), NotFoundException.Type.DISPUTE));
    }

    public List<Dispute> getSkipLocked(int limit, DisputeStatus disputeStatus) {
        var query = getDslContext().selectFrom(DISPUTE)
                .where(DISPUTE.STATUS.eq(disputeStatus)
                        .and(DISPUTE.NEXT_CHECK_AFTER.le(LocalDateTime.now(ZoneOffset.UTC))))
                .orderBy(DISPUTE.NEXT_CHECK_AFTER)
                .limit(limit)
                .forUpdate()
                .skipLocked();
        return Optional.ofNullable(fetch(query, disputeRowMapper))
                .orElse(List.of());
    }

    public List<Dispute> getForgottenSkipLocked(int limit) {
        var query = getDslContext().selectFrom(DISPUTE)
                .where(DISPUTE.STATUS.ne(DisputeStatus.created)
                        .and(DISPUTE.STATUS.ne(DisputeStatus.pending))
                        .and(DISPUTE.STATUS.ne(DisputeStatus.failed))
                        .and(DISPUTE.STATUS.ne(DisputeStatus.cancelled))
                        .and(DISPUTE.STATUS.ne(DisputeStatus.succeeded))
                        .and(DISPUTE.NEXT_CHECK_AFTER.le(LocalDateTime.now(ZoneOffset.UTC))))
                .orderBy(DISPUTE.NEXT_CHECK_AFTER)
                .limit(limit)
                .forUpdate()
                .skipLocked();
        return Optional.ofNullable(fetch(query, disputeRowMapper))
                .orElse(List.of());
    }

    public Dispute getByInvoiceId(String invoiceId, String paymentId) {
        var query = getDslContext().selectFrom(DISPUTE)
                .where(DISPUTE.INVOICE_ID.eq(invoiceId)
                        .and(DISPUTE.PAYMENT_ID.eq(paymentId)))
                .orderBy(DISPUTE.CREATED_AT.desc())
                .limit(1);
        return Optional.ofNullable(fetchOne(query, disputeRowMapper))
                .orElseThrow(() -> new NotFoundException(
                        String.format("Dispute not found, invoiceId='%s'", invoiceId), NotFoundException.Type.DISPUTE));
    }

    public Dispute getSkipLockedByInvoiceId(String invoiceId, String paymentId) {
        var query = getDslContext().selectFrom(DISPUTE)
                .where(DISPUTE.INVOICE_ID.eq(invoiceId)
                        .and(DISPUTE.PAYMENT_ID.eq(paymentId)))
                .orderBy(DISPUTE.CREATED_AT.desc())
                .limit(1)
                .forUpdate()
                .skipLocked();
        return Optional.ofNullable(fetchOne(query, disputeRowMapper))
                .orElseThrow(() -> new NotFoundException(
                        String.format("Dispute not found, invoiceId='%s'", invoiceId), NotFoundException.Type.DISPUTE));
    }

    public void updateNextPollingInterval(Dispute dispute, LocalDateTime nextCheckAfter) {
        update(dispute.getId(), dispute.getStatus(), nextCheckAfter, null, null, null);
    }

    public void setNextStepToCreated(UUID disputeId, LocalDateTime nextCheckAfter) {
        update(disputeId, DisputeStatus.created, nextCheckAfter, null, null, null);
    }

    public void setNextStepToPending(UUID disputeId, LocalDateTime nextCheckAfter) {
        update(disputeId, DisputeStatus.pending, nextCheckAfter, null, null, null);
    }

    public void setNextStepToCreateAdjustment(UUID disputeId, Long changedAmount) {
        update(disputeId, DisputeStatus.create_adjustment, null, null, changedAmount, null);
    }

    public void setNextStepToManualPending(UUID disputeId, String errorMessage) {
        update(disputeId, DisputeStatus.manual_pending, null, errorMessage, null, null);
    }

    public void setNextStepToAlreadyExist(UUID disputeId) {
        update(disputeId, DisputeStatus.already_exist_created, null, null, null, null);
    }

    public void setNextStepToPoolingExpired(UUID disputeId, String errorMessage) {
        update(disputeId, DisputeStatus.pooling_expired, null, errorMessage, null, null);
    }

    public void finishSucceeded(UUID disputeId, Long changedAmount) {
        update(disputeId, DisputeStatus.succeeded, null, null, changedAmount, null);
    }

    public void finishFailed(UUID disputeId, String errorMessage) {
        update(disputeId, DisputeStatus.failed, null, errorMessage, null, null);
    }

    public void finishFailedWithMapping(UUID disputeId, String errorMessage, String mapping) {
        update(disputeId, DisputeStatus.failed, null, errorMessage, null, mapping);
    }

    public void finishCancelled(UUID disputeId, String errorMessage, String mapping) {
        update(disputeId, DisputeStatus.cancelled, null, errorMessage, null, mapping);
    }

    private void update(UUID disputeId, DisputeStatus status, LocalDateTime nextCheckAfter, String errorMessage, Long changedAmount, String mapping) {
        var set = getDslContext().update(DISPUTE)
                .set(DISPUTE.STATUS, status);
        if (nextCheckAfter != null) {
            set = set.set(DISPUTE.NEXT_CHECK_AFTER, nextCheckAfter);
        }
        if (errorMessage != null) {
            set = set.set(DISPUTE.ERROR_MESSAGE, errorMessage);
        }
        if (mapping != null) {
            set = set.set(DISPUTE.MAPPING, mapping);
        }
        if (changedAmount != null) {
            set = set.set(DISPUTE.CHANGED_AMOUNT, changedAmount);
        }
        var query = set
                .where(DISPUTE.ID.eq(disputeId));
        executeOne(query);
    }
}


FILE: ./src/main/java/dev/vality/disputes/dao/FileMetaDao.java
MD5:  d20d0fe2d247462a98937da6c1f67a3e
SHA1: 869c87ae03df8c7c15879fa2aa64f8bc99bf4c7f
package dev.vality.disputes.dao;

import dev.vality.dao.impl.AbstractGenericDao;
import dev.vality.disputes.domain.tables.pojos.FileMeta;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.exception.NotFoundException.Type;
import dev.vality.mapper.RecordRowMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static dev.vality.disputes.domain.tables.FileMeta.FILE_META;

@Component
public class FileMetaDao extends AbstractGenericDao {

    private final RowMapper<FileMeta> fileMetaRowMapper;

    @Autowired
    public FileMetaDao(DataSource dataSource) {
        super(dataSource);
        fileMetaRowMapper = new RecordRowMapper<>(FILE_META, FileMeta.class);
    }

    public String save(FileMeta file) {
        var record = getDslContext().newRecord(FILE_META, file);
        var query = getDslContext().insertInto(FILE_META)
                .set(record);
        executeOne(query);
        return file.getFileId();
    }

    public List<FileMeta> getDisputeFiles(UUID disputeId) {
        var query = getDslContext().selectFrom(FILE_META)
                .where(FILE_META.DISPUTE_ID.eq(disputeId));
        return Optional.ofNullable(fetch(query, fileMetaRowMapper))
                .filter(fileMetas -> !fileMetas.isEmpty())
                .orElseThrow(() -> new NotFoundException(
                        String.format("FileMeta not found, disputeId='%s'", disputeId), Type.FILEMETA));

    }
}


FILE: ./src/main/java/dev/vality/disputes/dao/NotificationDao.java
MD5:  f8335da2ea63997634f140ad3cec7584
SHA1: 8bf520dd8057aff2fba75c74541c369b3dfc28bc
package dev.vality.disputes.dao;

import dev.vality.dao.impl.AbstractGenericDao;
import dev.vality.disputes.dao.mapper.NotifyRequestMapper;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.domain.enums.NotificationStatus;
import dev.vality.disputes.domain.tables.pojos.Notification;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.mapper.RecordRowMapper;
import dev.vality.swag.disputes.model.NotifyRequest;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static dev.vality.disputes.domain.tables.Dispute.DISPUTE;
import static dev.vality.disputes.domain.tables.Notification.NOTIFICATION;

@Component
@Slf4j
@SuppressWarnings({"LineLength"})
public class NotificationDao extends AbstractGenericDao {

    private final RowMapper<Notification> notificationRowMapper;
    private final NotifyRequestMapper notifyRequestMapper;

    @Autowired
    public NotificationDao(DataSource dataSource) {
        super(dataSource);
        notificationRowMapper = new RecordRowMapper<>(NOTIFICATION, Notification.class);
        notifyRequestMapper = new NotifyRequestMapper();
    }

    public void save(Notification notification) {
        var record = getDslContext().newRecord(NOTIFICATION, notification);
        var query = getDslContext().insertInto(NOTIFICATION)
                .set(record);
        executeOne(query);
    }

    public Notification get(UUID disputeId) {
        var query = getDslContext().selectFrom(NOTIFICATION)
                .where(NOTIFICATION.DISPUTE_ID.eq(disputeId));
        return Optional.ofNullable(fetchOne(query, notificationRowMapper))
                .orElseThrow(() -> new NotFoundException(
                        String.format("Notification not found, disputeId='%s'", disputeId), NotFoundException.Type.NOTIFICATION));
    }

    public Notification getSkipLocked(UUID disputeId) {
        var query = getDslContext().selectFrom(NOTIFICATION)
                .where(NOTIFICATION.DISPUTE_ID.eq(disputeId))
                .forUpdate()
                .skipLocked();
        return Optional.ofNullable(fetchOne(query, notificationRowMapper))
                .orElseThrow(() -> new NotFoundException(
                        String.format("Notification not found, disputeId='%s'", disputeId), NotFoundException.Type.NOTIFICATION));
    }

    public List<NotifyRequest> getNotifyRequests(int limit) {
        var query = getDslContext().select(
                        NOTIFICATION.DISPUTE_ID.as("dispute_id"),
                        DISPUTE.INVOICE_ID.as("invoice_id"),
                        DISPUTE.PAYMENT_ID.as("payment_id"),
                        DISPUTE.STATUS.as("dispute_status"),
                        DISPUTE.MAPPING.as("mapping"),
                        DISPUTE.CHANGED_AMOUNT.as("changed_amount")
                ).from(NOTIFICATION)
                .innerJoin(DISPUTE).on(NOTIFICATION.DISPUTE_ID.eq(DISPUTE.ID)
                        .and(DISPUTE.STATUS.in(DisputeStatus.succeeded, DisputeStatus.failed, DisputeStatus.cancelled)))
                .where(NOTIFICATION.NEXT_ATTEMPT_AFTER.le(LocalDateTime.now(ZoneOffset.UTC))
                        .and(NOTIFICATION.STATUS.eq(NotificationStatus.pending)))
                .orderBy(NOTIFICATION.NEXT_ATTEMPT_AFTER)
                .limit(limit);
        return Optional.ofNullable(fetch(query, notifyRequestMapper))
                .orElse(List.of());
    }

    public NotifyRequest getNotifyRequest(UUID disputeId) {
        var query = getDslContext().select(
                        NOTIFICATION.DISPUTE_ID.as("dispute_id"),
                        DISPUTE.INVOICE_ID.as("invoice_id"),
                        DISPUTE.PAYMENT_ID.as("payment_id"),
                        DISPUTE.STATUS.as("dispute_status"),
                        DISPUTE.MAPPING.as("mapping"),
                        DISPUTE.CHANGED_AMOUNT.as("changed_amount")
                ).from(NOTIFICATION)
                .innerJoin(DISPUTE).on(NOTIFICATION.DISPUTE_ID.eq(DISPUTE.ID)
                        .and(DISPUTE.STATUS.in(DisputeStatus.succeeded, DisputeStatus.failed, DisputeStatus.cancelled))
                        .and(DISPUTE.ID.eq(disputeId)));
        return Optional.ofNullable(fetchOne(query, notifyRequestMapper))
                .orElseThrow(() -> new NotFoundException(
                        String.format("Notification not found, disputeId='%s'", disputeId), NotFoundException.Type.NOTIFICATION));
    }

    public void delivered(Notification notification) {
        var query = getDslContext().update(NOTIFICATION)
                .set(NOTIFICATION.STATUS, NotificationStatus.delivered)
                .where(NOTIFICATION.DISPUTE_ID.eq(notification.getDisputeId()));
        executeOne(query);
    }

    public void updateNextAttempt(Notification notification, LocalDateTime nextAttemptAfter) {
        var set = getDslContext().update(NOTIFICATION)
                .set(NOTIFICATION.MAX_ATTEMPTS, NOTIFICATION.MAX_ATTEMPTS.minus(1))
                .set(NOTIFICATION.NEXT_ATTEMPT_AFTER, nextAttemptAfter);
        if (notification.getMaxAttempts() - 1 == 0) {
            set = set.set(NOTIFICATION.STATUS, NotificationStatus.attempts_limit);
        }
        var query = set
                .where(NOTIFICATION.DISPUTE_ID.eq(notification.getDisputeId()));
        executeOne(query);
    }
}


FILE: ./src/main/java/dev/vality/disputes/dao/ProviderDisputeDao.java
MD5:  380ce353a6ea1c387fc766a4b335c881
SHA1: d526d5b9dc8c86339b46c31068fff908608abee5
package dev.vality.disputes.dao;

import dev.vality.dao.impl.AbstractGenericDao;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.domain.tables.pojos.ProviderDispute;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.mapper.RecordRowMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.util.Optional;
import java.util.UUID;

import static dev.vality.disputes.domain.tables.ProviderDispute.PROVIDER_DISPUTE;
import static dev.vality.disputes.exception.NotFoundException.Type;

@Component
@Slf4j
public class ProviderDisputeDao extends AbstractGenericDao {

    private final RowMapper<ProviderDispute> providerDisputeRowMapper;

    @Autowired
    public ProviderDisputeDao(DataSource dataSource) {
        super(dataSource);
        providerDisputeRowMapper = new RecordRowMapper<>(PROVIDER_DISPUTE, ProviderDispute.class);
    }

    public void save(String providerDisputeId, Dispute dispute) {
        var id = save(new ProviderDispute(providerDisputeId, dispute.getId()));
        log.debug("ProviderDispute has been saved {}", id);
    }

    public UUID save(ProviderDispute providerDispute) {
        var record = getDslContext().newRecord(PROVIDER_DISPUTE, providerDispute);
        var query = getDslContext().insertInto(PROVIDER_DISPUTE)
                .set(record);
        executeOne(query);
        return providerDispute.getDisputeId();
    }

    public ProviderDispute get(UUID disputeId) {
        var query = getDslContext().selectFrom(PROVIDER_DISPUTE)
                .where(PROVIDER_DISPUTE.DISPUTE_ID.eq(disputeId));
        return Optional.ofNullable(fetchOne(query, providerDisputeRowMapper))
                .orElseThrow(() -> new NotFoundException(
                        String.format("ProviderDispute not found, disputeId='%s'", disputeId), Type.PROVIDERDISPUTE));
    }
}


FILE: ./src/main/java/dev/vality/disputes/dao/mapper/NotifyRequestMapper.java
MD5:  fa843563ee9e95db391dad8110344d6a
SHA1: f50a37e8257424f9ca3b13a23609da3ace9640b1
package dev.vality.disputes.dao.mapper;

import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.swag.disputes.model.GeneralError;
import dev.vality.swag.disputes.model.NotifyRequest;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Map;
import java.util.UUID;

public class NotifyRequestMapper implements RowMapper<NotifyRequest> {

    private static final Map<DisputeStatus, NotifyRequest.StatusEnum> STATUS_MAP = Map.of(
            DisputeStatus.succeeded, NotifyRequest.StatusEnum.SUCCEEDED,
            DisputeStatus.failed, NotifyRequest.StatusEnum.FAILED,
            DisputeStatus.cancelled, NotifyRequest.StatusEnum.FAILED
    );

    @Override
    public NotifyRequest mapRow(ResultSet rs, int i) throws SQLException {
        var request = new NotifyRequest();
        request.setDisputeId(rs.getObject("dispute_id", UUID.class).toString());
        request.setInvoiceId(rs.getString("invoice_id"));
        request.setPaymentId(rs.getString("payment_id"));
        var status = STATUS_MAP.get(DisputeStatus.valueOf(rs.getString("dispute_status")));
        request.setStatus(status);
        var mapping = rs.getString("mapping");
        if (mapping != null && !mapping.isBlank()) {
            request.setReason(new GeneralError(mapping));
        }
        var changedAmount = rs.getObject("changed_amount", Long.class);
        if (changedAmount != null) {
            request.setChangedAmount(changedAmount);
        }
        return request;
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/AuthorizationException.java
MD5:  2ebd07507c595c2be1d2a29d267a64c3
SHA1: ddee0ed97b822a262ce1d54ea1c59e5d3bc4c1f5
package dev.vality.disputes.exception;

public class AuthorizationException extends RuntimeException {

    public AuthorizationException(String s) {
        super(s);
    }

}


FILE: ./src/main/java/dev/vality/disputes/exception/BouncerException.java
MD5:  1d0d4231fa9d61698ea4923534722690
SHA1: 243516c384204c297d7d23b3c0ff0aed5509ae00
package dev.vality.disputes.exception;

public class BouncerException extends RuntimeException {

    public BouncerException(String s) {
        super(s);
    }

    public BouncerException(String message, Throwable cause) {
        super(message, cause);
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/CapturedPaymentException.java
MD5:  0789e7d9c6a87ede411c16a6c8ab009f
SHA1: 7c90c59ebe6c5f3688d468a214d0ffc90105a963
package dev.vality.disputes.exception;

import dev.vality.damsel.domain.InvoicePaymentCaptured;
import dev.vality.damsel.domain.InvoicePaymentStatus;
import dev.vality.damsel.payment_processing.InvoicePayment;
import lombok.Getter;

@Getter
public class CapturedPaymentException extends InvoicingPaymentStatusRestrictionsException {

    private final InvoicePayment invoicePayment;

    public CapturedPaymentException(InvoicePayment invoicePayment) {
        super(InvoicePaymentStatus.captured(new InvoicePaymentCaptured()));
        this.invoicePayment = invoicePayment;
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/DisputeStatusWasUpdatedByAnotherThreadException.java
MD5:  efca1634b9f808005ff2dc1d94886d0a
SHA1: 546490faf769830fee3e2a3761f478f526c5f7a2
package dev.vality.disputes.exception;

public class DisputeStatusWasUpdatedByAnotherThreadException extends RuntimeException {
}


FILE: ./src/main/java/dev/vality/disputes/exception/DominantException.java
MD5:  dcfd30ce367a4ba8f1ee660381bdd8e3
SHA1: a8b0bb8a8680d1b4e8d7f341a59da0d4247a9467
package dev.vality.disputes.exception;

public class DominantException extends RuntimeException {

    public DominantException(String message, Throwable cause) {
        super(message, cause);
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/FileStorageException.java
MD5:  df33f952976e62d3de63a3632de2742a
SHA1: db2d9be8fe42e0ed0064acbbf43864f6f0a1fefd
package dev.vality.disputes.exception;

public class FileStorageException extends RuntimeException {

    public FileStorageException(String message, Throwable cause) {
        super(message, cause);
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/InvoicePaymentAdjustmentPendingException.java
MD5:  714b30f9b2aa291b5e1e5ae4e5580148
SHA1: 18e905d8a300b146fd0f0f195581d556e743ccaa
package dev.vality.disputes.exception;

public class InvoicePaymentAdjustmentPendingException extends RuntimeException {

}


FILE: ./src/main/java/dev/vality/disputes/exception/InvoicingException.java
MD5:  e309f46ac87c2c464aa508422dbd72bb
SHA1: 962e3b8b535c8238d7cf9ebbec91384fda95db74
package dev.vality.disputes.exception;

public class InvoicingException extends RuntimeException {

    public InvoicingException(String message, Throwable cause) {
        super(message, cause);
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/InvoicingPaymentStatusRestrictionsException.java
MD5:  d7e4208ec5c0d3b2fce79489b9ff3e34
SHA1: 951d61b9bb0e61d729ff79a2c327aacd6abcdef9
package dev.vality.disputes.exception;

import dev.vality.damsel.domain.InvoicePaymentStatus;
import lombok.Getter;

@Getter
public class InvoicingPaymentStatusRestrictionsException extends RuntimeException {

    private final InvoicePaymentStatus status;

    public InvoicingPaymentStatusRestrictionsException(InvoicePaymentStatus status) {
        this.status = status;
    }

    public InvoicingPaymentStatusRestrictionsException(Throwable cause, InvoicePaymentStatus status) {
        super(cause);
        this.status = status;
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/NotFoundException.java
MD5:  d1e7edcdc7b7ddb46c4442d6bb2a61fc
SHA1: c4ee8a11b0b80d5ba18441b7221ab317dfbd19b4
package dev.vality.disputes.exception;

import lombok.Getter;

@Getter
public class NotFoundException extends RuntimeException {

    private final Type type;

    public NotFoundException(String message, Type type) {
        super(message);
        this.type = type;
    }

    public NotFoundException(String message, Throwable cause, Type type) {
        super(message, cause);
        this.type = type;
    }

    public enum Type {
        INVOICE,
        PAYMENT,
        ATTACHMENT,
        FILEMETA,
        TERMINAL,
        PROVIDER,
        PROXY,
        CURRENCY,
        PARTY,
        SHOP,
        PROVIDERTRXID,
        DISPUTE,
        PROVIDERDISPUTE,
        PROVIDERCALLBACK,
        NOTIFICATION
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/NotificationNotFinalStatusException.java
MD5:  9260cd4c069289e76a792b1b4bd0d310
SHA1: abb776782eb33165e20994c38cb66d6dc5cb57a7
package dev.vality.disputes.exception;

public class NotificationNotFinalStatusException extends RuntimeException {

    public NotificationNotFinalStatusException(String format) {
        super(format);
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/NotificationStatusWasUpdatedByAnotherThreadException.java
MD5:  3963108551ab8caf8d7d4ab83351246e
SHA1: 845b90b374c9a787db1bc35c1171861d5cef89dc
package dev.vality.disputes.exception;

public class NotificationStatusWasUpdatedByAnotherThreadException extends RuntimeException {
}


FILE: ./src/main/java/dev/vality/disputes/exception/PartyException.java
MD5:  93a97fc4ba9e347fb9c668e08a3d7375
SHA1: d0c254bf311fee4c3a43d6f0d2425d9658a194f1
package dev.vality.disputes.exception;

public class PartyException extends RuntimeException {

    public PartyException(String message, Throwable cause) {
        super(message, cause);
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/PoolingExpiredException.java
MD5:  9a38cab554663666d7264cfa4e64021e
SHA1: 588e1ef3361981177e886df95b3d9c66ca2c7b84
package dev.vality.disputes.exception;

public class PoolingExpiredException extends RuntimeException {

    public PoolingExpiredException() {
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/RoutingException.java
MD5:  6d5d8939ecb3232cf21d043d4aeb2662
SHA1: be206a65a751791566e452a370702993aa85ad9c
package dev.vality.disputes.exception;

public class RoutingException extends RuntimeException {

    public RoutingException(String message, Throwable cause) {
        super(message, cause);
    }
}


FILE: ./src/main/java/dev/vality/disputes/exception/TokenKeeperException.java
MD5:  e1a7ca85a93bd34c879289cda8d4f6d9
SHA1: c690d0560df16ae770fc32f8d052ed9340a60f15
package dev.vality.disputes.exception;

public class TokenKeeperException extends RuntimeException {

    public TokenKeeperException(String s) {
        super(s);
    }

    public TokenKeeperException(String message, Throwable cause) {
        super(message, cause);
    }
}


FILE: ./src/main/java/dev/vality/disputes/flow/DisputesStepResolver.java
MD5:  49f9d00dd62d4f2c7dfe1b1e6c3aa263
SHA1: 318d99900535dfea0ba0c7377fdb626bd45a7846
package dev.vality.disputes.flow;

import dev.vality.damsel.domain.Failure;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.util.ErrorFormatter;
import dev.vality.woody.api.flow.error.WRuntimeException;

import static dev.vality.disputes.constant.ModerationPrefix.DISPUTES_UNKNOWN_MAPPING;

@SuppressWarnings({"LineLength"})
public class DisputesStepResolver {

    public DisputeStatus resolveNextStep(
            DisputeStatus status, Boolean isDefaultRouteUrl, Failure failure,
            Boolean isAlreadyExistResult, WRuntimeException unexpectedResultMapping, String handleFailedResultErrorMessage,
            Boolean isSuccessDisputeCheckStatusResult, Boolean isPoolingExpired, Boolean isProviderDisputeNotFound,
            Boolean isAdminApproveCall, Boolean isAdminCancelCall, Boolean isAdminBindCall, Boolean isSkipHgCallApproveFlag,
            Boolean isSuccessProviderPaymentStatus, Boolean isSetPendingForPoolingExpired, Boolean isInvoicePaymentStatusCaptured) {
        return switch (status) {
            case created -> {
                if (isAdminCancelCall) {
                    yield DisputeStatus.cancelled;
                }
                if (isInvoicePaymentStatusCaptured) {
                    yield DisputeStatus.succeeded;
                }
                if (isSuccessProviderPaymentStatus) {
                    yield DisputeStatus.create_adjustment;
                }
                if (handleFailedResultErrorMessage != null) {
                    yield DisputeStatus.failed;
                }
                if (failure != null) {
                    var errorMessage = ErrorFormatter.getErrorMessage(failure);
                    if (errorMessage.startsWith(DISPUTES_UNKNOWN_MAPPING)) {
                        yield DisputeStatus.manual_pending;
                    }
                    yield DisputeStatus.failed;
                }
                if (isAlreadyExistResult) {
                    yield DisputeStatus.already_exist_created;
                }
                if (isDefaultRouteUrl) {
                    yield DisputeStatus.manual_pending;
                }
                yield DisputeStatus.pending;
            }
            case pending -> {
                if (isAdminCancelCall) {
                    yield DisputeStatus.cancelled;
                }
                if (isInvoicePaymentStatusCaptured) {
                    yield DisputeStatus.succeeded;
                }
                if (isAdminApproveCall && !isSkipHgCallApproveFlag) {
                    yield DisputeStatus.create_adjustment;
                }
                if (isAdminApproveCall) {
                    yield DisputeStatus.succeeded;
                }
                if (handleFailedResultErrorMessage != null) {
                    yield DisputeStatus.failed;
                }
                if (isPoolingExpired) {
                    yield DisputeStatus.pooling_expired;
                }
                if (isProviderDisputeNotFound) {
                    yield DisputeStatus.created;
                }
                if (unexpectedResultMapping != null) {
                    yield DisputeStatus.manual_pending;
                }
                if (failure != null) {
                    var errorMessage = ErrorFormatter.getErrorMessage(failure);
                    if (errorMessage.startsWith(DISPUTES_UNKNOWN_MAPPING)) {
                        yield DisputeStatus.manual_pending;
                    }
                    yield DisputeStatus.failed;
                }
                if (!isSuccessDisputeCheckStatusResult) {
                    yield DisputeStatus.pending;
                }
                yield DisputeStatus.create_adjustment;
            }
            case create_adjustment -> {
                if (isInvoicePaymentStatusCaptured) {
                    yield DisputeStatus.succeeded;
                }
                if (isAdminCancelCall) {
                    yield DisputeStatus.cancelled;
                }
                if (isAdminApproveCall) {
                    yield DisputeStatus.succeeded;
                }
                if (handleFailedResultErrorMessage != null) {
                    yield DisputeStatus.failed;
                }
                yield DisputeStatus.succeeded;
            }
            case manual_pending -> {
                if (isInvoicePaymentStatusCaptured) {
                    yield DisputeStatus.succeeded;
                }
                if (isAdminCancelCall) {
                    yield DisputeStatus.cancelled;
                }
                if (isAdminApproveCall && !isSkipHgCallApproveFlag) {
                    yield DisputeStatus.create_adjustment;
                }
                if (isAdminApproveCall) {
                    yield DisputeStatus.succeeded;
                }
                throw new DeadEndFlowException();
            }
            case already_exist_created -> {
                if (isInvoicePaymentStatusCaptured) {
                    yield DisputeStatus.succeeded;
                }
                if (isAdminCancelCall) {
                    yield DisputeStatus.cancelled;
                }
                if (isAdminBindCall) {
                    yield DisputeStatus.pending;
                }
                throw new DeadEndFlowException();
            }
            case pooling_expired -> {
                if (isInvoicePaymentStatusCaptured) {
                    yield DisputeStatus.succeeded;
                }
                if (isAdminCancelCall) {
                    yield DisputeStatus.cancelled;
                }
                if (isAdminApproveCall && !isSkipHgCallApproveFlag) {
                    yield DisputeStatus.create_adjustment;
                }
                if (isAdminApproveCall) {
                    yield DisputeStatus.succeeded;
                }
                if (isSetPendingForPoolingExpired) {
                    yield DisputeStatus.pending;
                }
                throw new DeadEndFlowException();
            }
            case cancelled -> DisputeStatus.cancelled;
            case failed -> DisputeStatus.failed;
            case succeeded -> DisputeStatus.succeeded;
            default -> throw new DeadEndFlowException();
        };
    }

    public static class DeadEndFlowException extends RuntimeException {
    }
}


FILE: ./src/main/java/dev/vality/disputes/merchant/MerchantDisputesHandler.java
MD5:  f3653a2ae6eec958bf09a14fc194bd5d
SHA1: e17b501715ddeaf527c8760ed082843261a15e01
package dev.vality.disputes.merchant;

import dev.vality.disputes.api.DisputesApiDelegate;
import dev.vality.disputes.merchant.converter.CreateRequestConverter;
import dev.vality.swag.disputes.model.GeneralError;
import dev.vality.swag.disputes.model.Status200Response;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.Optional;

@Service
@RequiredArgsConstructor
@Slf4j
@SuppressWarnings({"LineLength"})
public class MerchantDisputesHandler implements MerchantDisputesServiceSrv.Iface {

    private final CreateRequestConverter createRequestConverter;
    private final DisputesApiDelegate disputesApiDelegate;

    @Override
    public DisputeCreatedResult createDispute(DisputeParams disputeParams) {
        log.debug("Got DisputeParams {}", disputeParams);
        var createRequest = createRequestConverter.convert(disputeParams);
        var disputeId = disputesApiDelegate.create(createRequest, false)
                .getBody()
                .getDisputeId();
        log.debug("Finish DisputeParams {}", disputeParams);
        return DisputeCreatedResult.successResult(new DisputeCreatedSuccessResult(disputeId));
    }

    @Override
    public DisputeStatusResult checkDisputeStatus(DisputeContext disputeContext) {
        log.debug("Got DisputeContext {}", disputeContext);
        var response = disputesApiDelegate.status(disputeContext.getDisputeId(), false).getBody();
        log.debug("Finish DisputeContext {}", disputeContext);
        return switch (response.getStatus()) {
            case PENDING -> DisputeStatusResult.statusPending(new DisputeStatusPendingResult());
            case FAILED -> DisputeStatusResult.statusFail(
                    new DisputeStatusFailResult().setMapping(getMapping(response)));
            case SUCCEEDED -> DisputeStatusResult.statusSuccess(
                    getDisputeStatusSuccessResult(response));
        };
    }

    private DisputeStatusSuccessResult getDisputeStatusSuccessResult(Status200Response response) {
        var disputeStatusSuccessResult = new DisputeStatusSuccessResult();
        if (response.getChangedAmount() != null) {
            disputeStatusSuccessResult.setChangedAmount(response.getChangedAmount());
        }
        return disputeStatusSuccessResult;
    }

    private String getMapping(Status200Response response) {
        return Optional.ofNullable(response.getReason())
                .map(GeneralError::getMessage)
                .orElse(null);
    }
}


FILE: ./src/main/java/dev/vality/disputes/merchant/converter/CreateRequestConverter.java
MD5:  3d3279463617f017c77cefe21019aded
SHA1: ed1d21203cc65b60d8b1d31a7f20e2ca730d1e76
package dev.vality.disputes.merchant.converter;

import dev.vality.disputes.merchant.DisputeParams;
import dev.vality.swag.disputes.model.CreateRequest;
import dev.vality.swag.disputes.model.CreateRequestAttachmentsInner;
import org.springframework.stereotype.Component;

import java.util.stream.Collectors;

@Component
@SuppressWarnings({"LineLength"})
public class CreateRequestConverter {

    public CreateRequest convert(DisputeParams disputeParams) {
        return new CreateRequest(
                disputeParams.getInvoiceId(),
                disputeParams.getPaymentId(),
                disputeParams.getAttachments().stream()
                        .map(attachment -> new CreateRequestAttachmentsInner(attachment.getData(), attachment.getMimeType()))
                        .collect(Collectors.toList()))
                .notificationUrl(disputeParams.getNotificationUrl().orElse(null));
    }
}


FILE: ./src/main/java/dev/vality/disputes/polling/ExponentialBackOffPollingService.java
MD5:  3b0176da19098e4358c2aeffab9f3832
SHA1: 647c647eee7e53782ae0ff9fdd3ff43e263ad64f
package dev.vality.disputes.polling;

import dev.vality.adapter.flow.lib.model.PollingInfo;
import dev.vality.adapter.flow.lib.utils.backoff.ExponentialBackOff;

import java.time.Instant;
import java.util.Map;

import static dev.vality.adapter.flow.lib.utils.backoff.ExponentialBackOff.*;

public class ExponentialBackOffPollingService {

    public int prepareNextPollingInterval(PollingInfo pollingInfo, Map<String, String> options) {
        return exponentialBackOff(pollingInfo, options)
                .start()
                .nextBackOff()
                .intValue();
    }

    private ExponentialBackOff exponentialBackOff(PollingInfo pollingInfo, Map<String, String> options) {
        final var currentLocalTime = Instant.now().toEpochMilli();
        var startTime = pollingInfo.getStartDateTimePolling() != null
                ? pollingInfo.getStartDateTimePolling().toEpochMilli()
                : currentLocalTime;
        var exponential = TimeOptionsExtractors.extractExponent(options, DEFAULT_MUTIPLIER);
        var defaultInitialExponential =
                TimeOptionsExtractors.extractDefaultInitialExponential(options, DEFAULT_INITIAL_INTERVAL_SEC);
        var maxTimeBackOff = TimeOptionsExtractors.extractMaxTimeBackOff(options, DEFAULT_MAX_INTERVAL_SEC);
        return new ExponentialBackOff(
                startTime,
                currentLocalTime,
                exponential,
                defaultInitialExponential,
                maxTimeBackOff);
    }
}


FILE: ./src/main/java/dev/vality/disputes/polling/ExponentialBackOffPollingServiceWrapper.java
MD5:  49f9ab9d84202ca98f1da3ed750c0b5f
SHA1: ddaeee572cd3d2703c4ace5ec16f5eb427195606
package dev.vality.disputes.polling;

import dev.vality.adapter.flow.lib.model.PollingInfo;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.domain.tables.pojos.Notification;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Map;

@Service
@SuppressWarnings({"LineLength"})
public class ExponentialBackOffPollingServiceWrapper {

    private final ExponentialBackOffPollingService exponentialBackOffPollingService;

    public ExponentialBackOffPollingServiceWrapper() {
        this.exponentialBackOffPollingService = new ExponentialBackOffPollingService();
    }

    public LocalDateTime prepareNextPollingInterval(PollingInfo pollingInfo, Map<String, String> options) {
        var seconds = exponentialBackOffPollingService.prepareNextPollingInterval(pollingInfo, options);
        return getLocalDateTime(pollingInfo.getStartDateTimePolling().plusSeconds(seconds));
    }

    public LocalDateTime prepareNextPollingInterval(Dispute dispute, Map<String, String> options) {
        var pollingInfo = new PollingInfo();
        var startDateTimePolling = dispute.getCreatedAt().toInstant(ZoneOffset.UTC);
        pollingInfo.setStartDateTimePolling(startDateTimePolling);
        var seconds = exponentialBackOffPollingService.prepareNextPollingInterval(pollingInfo, options);
        return getLocalDateTime(dispute.getNextCheckAfter().toInstant(ZoneOffset.UTC).plusSeconds(seconds));
    }

    public LocalDateTime prepareNextPollingInterval(Notification notification, LocalDateTime createdAt, Map<String, String> options) {
        var pollingInfo = new PollingInfo();
        pollingInfo.setStartDateTimePolling(createdAt.toInstant(ZoneOffset.UTC));
        var seconds = exponentialBackOffPollingService.prepareNextPollingInterval(pollingInfo, options);
        return getLocalDateTime(
                notification.getNextAttemptAfter().toInstant(ZoneOffset.UTC).plusSeconds(seconds));
    }

    private LocalDateTime getLocalDateTime(Instant instant) {
        return LocalDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}


FILE: ./src/main/java/dev/vality/disputes/polling/PollingInfoService.java
MD5:  f34c94b332b903e5875a6cb1b0285aa3
SHA1: 385a668e973e603798f644adaab8abd7b18a3dcf
package dev.vality.disputes.polling;

import dev.vality.adapter.flow.lib.model.PollingInfo;
import dev.vality.disputes.config.properties.DisputesTimerProperties;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.exception.PoolingExpiredException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.Optional;

import static dev.vality.disputes.util.OptionsExtractor.extractMaxTimePolling;

@Service
@RequiredArgsConstructor
public class PollingInfoService {

    private final DisputesTimerProperties timerProperties;

    public PollingInfo initPollingInfo(Map<String, String> options) {
        return initPollingInfo(new PollingInfo(), options);
    }

    public PollingInfo initPollingInfo(PollingInfo pollingInfo, Map<String, String> options) {
        if (pollingInfo == null) {
            pollingInfo = new PollingInfo();
        }
        if (pollingInfo.getStartDateTimePolling() == null) {
            pollingInfo.setStartDateTimePolling(Instant.now());
        }
        var maxDateTimePolling = calcDeadline(pollingInfo, options);
        pollingInfo.setMaxDateTimePolling(maxDateTimePolling);
        return pollingInfo;
    }

    public void checkDeadline(Dispute dispute) {
        if (isDeadline(convert(dispute))) {
            throw new PoolingExpiredException();
        }
    }

    private boolean isDeadline(PollingInfo pollingInfo) {
        var now = Instant.now();
        return now.isAfter(pollingInfo.getMaxDateTimePolling());
    }

    private Instant calcDeadline(PollingInfo pollingInfo, Map<String, String> options) {
        if (pollingInfo.getMaxDateTimePolling() == null) {
            var maxTimePolling = extractMaxTimePolling(options, timerProperties.getMaxTimePollingMin());
            return pollingInfo.getStartDateTimePolling().plus(maxTimePolling, ChronoUnit.MINUTES);
        }
        return pollingInfo.getMaxDateTimePolling();
    }

    private PollingInfo convert(Dispute dispute) {
        return Optional.ofNullable(dispute)
                .map(d -> {
                    var p = new PollingInfo();
                    p.setStartDateTimePolling(d.getCreatedAt().toInstant(ZoneOffset.UTC));
                    p.setMaxDateTimePolling(d.getPollingBefore().toInstant(ZoneOffset.UTC));
                    return p;
                })
                .orElse(new PollingInfo());
    }
}


FILE: ./src/main/java/dev/vality/disputes/polling/TimeOptionsExtractors.java
MD5:  66f45d1f89559e4f6f6c67863d9d30ce
SHA1: b45bc678bf240dc997796066cf2aca756ffdb030
package dev.vality.disputes.polling;

import lombok.AccessLevel;
import lombok.NoArgsConstructor;

import java.util.Map;

@NoArgsConstructor(access = AccessLevel.PRIVATE)
public class TimeOptionsExtractors {

    public static final String TIMER_EXPONENTIAL = "exponential";
    public static final String MAX_TIME_BACKOFF_SEC = "max_time_backoff_sec";
    public static final String DEFAULT_INITIAL_EXPONENTIAL_SEC = "default_initial_exponential_sec";
    public static final String DISPUTE_TIMER_EXPONENTIAL = "dispute_exponential";
    public static final String DISPUTE_MAX_TIME_BACKOFF_SEC = "dispute_max_time_backoff_sec";
    public static final String DISPUTE_DEFAULT_INITIAL_EXPONENTIAL_SEC = "dispute_default_initial_exponential_sec";

    public static Integer extractExponent(Map<String, String> options, int maxTimePolling) {
        return Integer.parseInt(options.getOrDefault(
                DISPUTE_TIMER_EXPONENTIAL,
                options.getOrDefault(TIMER_EXPONENTIAL, String.valueOf(maxTimePolling))));
    }

    public static Integer extractMaxTimeBackOff(Map<String, String> options, int maxTimeBackOff) {
        return Integer.parseInt(options.getOrDefault(
                DISPUTE_MAX_TIME_BACKOFF_SEC,
                options.getOrDefault(MAX_TIME_BACKOFF_SEC, String.valueOf(maxTimeBackOff))));
    }

    public static Integer extractDefaultInitialExponential(Map<String, String> options, int defaultInitialExponential) {
        return Integer.parseInt(
                options.getOrDefault(DISPUTE_DEFAULT_INITIAL_EXPONENTIAL_SEC,
                        options.getOrDefault(DEFAULT_INITIAL_EXPONENTIAL_SEC, String.valueOf(
                                defaultInitialExponential))));
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/callback/ProviderPaymentsCallbackHandler.java
MD5:  2ff3fb6380100f5faf4079bcd2e525b7
SHA1: 9b246f8933138e14cfaf9bc57311f3a1623a2b80
package dev.vality.disputes.provider.payments.callback;

import dev.vality.disputes.provider.payments.service.ProviderPaymentsService;
import dev.vality.provider.payments.ProviderPaymentsCallbackParams;
import dev.vality.provider.payments.ProviderPaymentsCallbackServiceSrv;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
@Slf4j
@SuppressWarnings({"LineLength"})
public class ProviderPaymentsCallbackHandler implements ProviderPaymentsCallbackServiceSrv.Iface {

    private final ProviderPaymentsService providerPaymentsService;

    @Value("${provider.payments.isProviderCallbackEnabled}")
    private boolean isProviderCallbackEnabled;

    @Override
    public void createAdjustmentWhenFailedPaymentSuccess(ProviderPaymentsCallbackParams callback) {
        log.info("Got providerPaymentsCallbackParams {}", callback);
        if (!isProviderCallbackEnabled) {
            return;
        }
        if (callback.getInvoiceId().isEmpty() && callback.getPaymentId().isEmpty()) {
            log.debug("InvoiceId should be set, finish");
            return;
        }
        providerPaymentsService.processCallback(callback);
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/client/ProviderPaymentsRemoteClient.java
MD5:  6c9871e2b826b0c8634ae5bb2b5d240a
SHA1: a8af23d86b2424a694928cc6621daff41456abbb
package dev.vality.disputes.provider.payments.client;

import dev.vality.damsel.domain.Currency;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsRouting;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsThriftInterfaceBuilder;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.provider.payments.PaymentStatusResult;
import dev.vality.provider.payments.TransactionContext;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ProviderPaymentsRemoteClient {

    private final ProviderPaymentsRouting providerPaymentsRouting;
    private final ProviderPaymentsThriftInterfaceBuilder providerPaymentsThriftInterfaceBuilder;

    @SneakyThrows
    public PaymentStatusResult checkPaymentStatus(TransactionContext transactionContext, Currency currency, ProviderData providerData) {
        log.info("Trying to call ProviderPaymentsThriftInterfaceBuilder.checkPaymentStatus() {}", transactionContext);
        providerPaymentsRouting.initRouteUrl(providerData);
        var remoteClient = providerPaymentsThriftInterfaceBuilder.buildWoodyClient(providerData.getRouteUrl());
        return remoteClient.checkPaymentStatus(transactionContext, currency);
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/converter/ProviderPaymentsToInvoicePaymentCapturedAdjustmentParamsConverter.java
MD5:  8fb5266b9b01942b863a29ef751bbc15
SHA1: fb50fafdd25d8b8cacbbaf5dd8bf7541a7da8dd1
package dev.vality.disputes.provider.payments.converter;

import dev.vality.damsel.domain.InvoicePaymentAdjustmentStatusChange;
import dev.vality.damsel.domain.InvoicePaymentCaptured;
import dev.vality.damsel.domain.InvoicePaymentStatus;
import dev.vality.damsel.payment_processing.InvoicePaymentAdjustmentParams;
import dev.vality.damsel.payment_processing.InvoicePaymentAdjustmentScenario;
import dev.vality.disputes.domain.tables.pojos.ProviderCallback;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsAdjustmentExtractor;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class ProviderPaymentsToInvoicePaymentCapturedAdjustmentParamsConverter {

    private final ProviderPaymentsAdjustmentExtractor providerPaymentsAdjustmentExtractor;

    public InvoicePaymentAdjustmentParams convert(ProviderCallback providerCallback) {
        var captured = new InvoicePaymentCaptured();
        var reason = providerPaymentsAdjustmentExtractor.getReason(providerCallback);
        captured.setReason(reason);
        var params = new InvoicePaymentAdjustmentParams();
        params.setReason(reason);
        params.setScenario(getInvoicePaymentAdjustmentScenario(captured));
        return params;
    }

    private InvoicePaymentAdjustmentScenario getInvoicePaymentAdjustmentScenario(InvoicePaymentCaptured captured) {
        return InvoicePaymentAdjustmentScenario.status_change(new InvoicePaymentAdjustmentStatusChange(
                InvoicePaymentStatus.captured(captured)));
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/converter/ProviderPaymentsToInvoicePaymentCashFlowAdjustmentParamsConverter.java
MD5:  9f58a9164ccdc354c2ab86368cc7e4d6
SHA1: ee1f3dcd3fb9394b6683664b9d7c048c3bfbd438
package dev.vality.disputes.provider.payments.converter;

import dev.vality.damsel.domain.InvoicePaymentAdjustmentCashFlow;
import dev.vality.damsel.payment_processing.InvoicePaymentAdjustmentParams;
import dev.vality.damsel.payment_processing.InvoicePaymentAdjustmentScenario;
import dev.vality.disputes.domain.tables.pojos.ProviderCallback;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsAdjustmentExtractor;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class ProviderPaymentsToInvoicePaymentCashFlowAdjustmentParamsConverter {

    private final ProviderPaymentsAdjustmentExtractor providerPaymentsAdjustmentExtractor;

    public InvoicePaymentAdjustmentParams convert(ProviderCallback providerCallback) {
        var params = new InvoicePaymentAdjustmentParams();
        params.setReason(providerPaymentsAdjustmentExtractor.getReason(providerCallback));
        params.setScenario(getInvoicePaymentAdjustmentScenario(providerCallback.getChangedAmount()));
        return params;
    }

    private InvoicePaymentAdjustmentScenario getInvoicePaymentAdjustmentScenario(Long changedAmount) {
        return InvoicePaymentAdjustmentScenario.cash_flow(new InvoicePaymentAdjustmentCashFlow()
                .setNewAmount(changedAmount));
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/converter/TransactionContextConverter.java
MD5:  f54dffaa83576f4e5b38373154d39ca8
SHA1: 78bfffa7c3b3c6b8bea327f3429f62bf74f6afb6
package dev.vality.disputes.provider.payments.converter;

import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.provider.payments.TransactionContext;
import org.springframework.stereotype.Component;

@Component
@SuppressWarnings({"LineLength"})
public class TransactionContextConverter {

    public TransactionContext convert(String invoiceId, String paymentId, String providerTrxId, ProviderData providerData, TransactionInfo transactionInfo) {
        var transactionContext = new TransactionContext();
        transactionContext.setProviderTrxId(providerTrxId);
        transactionContext.setInvoiceId(invoiceId);
        transactionContext.setPaymentId(paymentId);
        transactionContext.setTerminalOptions(providerData.getOptions());
        transactionContext.setTransactionInfo(transactionInfo);
        return transactionContext;
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/dao/ProviderCallbackDao.java
MD5:  167b9963d601b57feaccf9ceabae84c1
SHA1: 5c99060254439a15331245ec655e87aeeaa1a71b
package dev.vality.disputes.provider.payments.dao;

import dev.vality.dao.impl.AbstractGenericDao;
import dev.vality.disputes.domain.enums.ProviderPaymentsStatus;
import dev.vality.disputes.domain.tables.pojos.ProviderCallback;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.mapper.RecordRowMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static dev.vality.disputes.domain.tables.ProviderCallback.PROVIDER_CALLBACK;

@Component
@SuppressWarnings({"LineLength"})
public class ProviderCallbackDao extends AbstractGenericDao {

    private final RowMapper<ProviderCallback> providerCallbackRowMapper;

    @Autowired
    public ProviderCallbackDao(DataSource dataSource) {
        super(dataSource);
        providerCallbackRowMapper = new RecordRowMapper<>(PROVIDER_CALLBACK, ProviderCallback.class);
    }

    public UUID save(ProviderCallback providerCallback) {
        var record = getDslContext().newRecord(PROVIDER_CALLBACK, providerCallback);
        var query = getDslContext().insertInto(PROVIDER_CALLBACK)
                .set(record)
                .returning(PROVIDER_CALLBACK.ID);
        var keyHolder = new GeneratedKeyHolder();
        execute(query, keyHolder);
        return Optional.ofNullable(keyHolder.getKeyAs(UUID.class)).orElseThrow();
    }

    public ProviderCallback getProviderCallbackForUpdateSkipLocked(UUID id) {
        var query = getDslContext().selectFrom(PROVIDER_CALLBACK)
                .where(PROVIDER_CALLBACK.ID.eq(id))
                .forUpdate()
                .skipLocked();
        return Optional.ofNullable(fetchOne(query, providerCallbackRowMapper))
                .orElseThrow(() -> new NotFoundException(
                        String.format("ProviderCallback not found, id='%s'", id), NotFoundException.Type.PROVIDERCALLBACK));
    }

    public ProviderCallback get(String invoiceId, String paymentId) {
        var query = getDslContext().selectFrom(PROVIDER_CALLBACK)
                .where(PROVIDER_CALLBACK.INVOICE_ID.concat(PROVIDER_CALLBACK.PAYMENT_ID).eq(invoiceId + paymentId));
        return Optional.ofNullable(fetchOne(query, providerCallbackRowMapper))
                .orElseThrow(() -> new NotFoundException(
                        String.format("ProviderCallback not found, id='%s%s'", invoiceId, paymentId), NotFoundException.Type.PROVIDERCALLBACK));

    }

    public List<ProviderCallback> getProviderCallbacksForHgCall(int limit) {
        var query = getDslContext().selectFrom(PROVIDER_CALLBACK)
                .where(PROVIDER_CALLBACK.STATUS.eq(ProviderPaymentsStatus.create_adjustment))
                .limit(limit)
                .forUpdate()
                .skipLocked();
        return Optional.ofNullable(fetch(query, providerCallbackRowMapper))
                .orElse(List.of());
    }

    public void update(ProviderCallback providerCallback) {
        var record = getDslContext().newRecord(PROVIDER_CALLBACK, providerCallback);
        var query = getDslContext().update(PROVIDER_CALLBACK)
                .set(record)
                .where(PROVIDER_CALLBACK.ID.eq(providerCallback.getId()));
        execute(query);
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/exception/ProviderCallbackAlreadyExistException.java
MD5:  dce778beaa9ca0c52cd1d183e1443c56
SHA1: c7fb5411694082348ab3b4e5e0b32af1f893b6f1
package dev.vality.disputes.provider.payments.exception;

public class ProviderCallbackAlreadyExistException extends RuntimeException {
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/exception/ProviderCallbackStatusWasUpdatedByAnotherThreadException.java
MD5:  98ee0b79a79cf915428be62b7d758a63
SHA1: 759d04e00449ad91d0a57273b2dd6ba87a6098f5
package dev.vality.disputes.provider.payments.exception;

public class ProviderCallbackStatusWasUpdatedByAnotherThreadException extends RuntimeException {
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/exception/ProviderPaymentsUnexpectedPaymentStatus.java
MD5:  271bb7c25afb7cc36296399ad8d38ae5
SHA1: cffb97a028219bdac62814d73477f74dea59f8fa
package dev.vality.disputes.provider.payments.exception;

public class ProviderPaymentsUnexpectedPaymentStatus extends RuntimeException {

    public ProviderPaymentsUnexpectedPaymentStatus(String message) {
        super(message);
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/handler/ProviderPaymentHandler.java
MD5:  817129974070d3fcaa8072e1f57a45c1
SHA1: 2484bdecf7dafc68618929eca8d50744a2acc6a6
package dev.vality.disputes.provider.payments.handler;

import dev.vality.disputes.domain.tables.pojos.ProviderCallback;
import dev.vality.disputes.exception.InvoicePaymentAdjustmentPendingException;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import java.util.UUID;

@RequiredArgsConstructor
@Slf4j
public class ProviderPaymentHandler {

    private final ProviderPaymentsService providerPaymentsService;

    public UUID handle(ProviderCallback providerCallback) {
        final var currentThread = Thread.currentThread();
        final var oldName = currentThread.getName();
        currentThread.setName("provider-payments-" + providerCallback.getInvoiceId() +
                "." + providerCallback.getPaymentId() + "-" + oldName);
        try {
            providerPaymentsService.callHgForCreateAdjustment(providerCallback);
            return providerCallback.getId();
        } catch (InvoicePaymentAdjustmentPendingException ignored) {
            return providerCallback.getId();
        } catch (Throwable ex) {
            log.error("Received exception while scheduler processed ProviderPayments callHgForCreateAdjustment", ex);
            throw ex;
        } finally {
            currentThread.setName(oldName);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/schedule/ProviderPaymentsTask.java
MD5:  f39a36db85f939e8fe902c347896b02f
SHA1: dcc427db1d5abb376c7050108226760b21213634
package dev.vality.disputes.provider.payments.schedule;

import dev.vality.disputes.domain.tables.pojos.ProviderCallback;
import dev.vality.disputes.provider.payments.handler.ProviderPaymentHandler;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.stream.Collectors;

@Slf4j
@ConditionalOnProperty(value = "provider.payments.isScheduleCreateAdjustmentsEnabled", havingValue = "true")
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ProviderPaymentsTask {

    private final ExecutorService providerPaymentsThreadPool;
    private final ProviderPaymentsService providerPaymentsService;

    @Value("${provider.payments.batchSize}")
    private int batchSize;

    @Scheduled(fixedDelayString = "${provider.payments.fixedDelayCreateAdjustments}", initialDelayString = "${provider.payments.initialDelayCreateAdjustments}")
    public void processPending() {
        try {
            var paymentsForHgCall = providerPaymentsService.getPaymentsForHgCall(batchSize);
            var callables = paymentsForHgCall.stream()
                    .map(this::handleProviderPaymentsCreateAdjustment)
                    .collect(Collectors.toList());
            providerPaymentsThreadPool.invokeAll(callables);
        } catch (InterruptedException ex) {
            log.error("Received InterruptedException while thread executed report", ex);
            Thread.currentThread().interrupt();
        } catch (Throwable ex) {
            log.error("Received exception while scheduler processed ProviderPayments create adjustments", ex);
        }
    }

    private Callable<UUID> handleProviderPaymentsCreateAdjustment(ProviderCallback providerCallback) {
        return () -> new ProviderPaymentHandler(providerPaymentsService).handle(providerCallback);
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/service/ProviderPaymentsAdjustmentExtractor.java
MD5:  b3dce0570700d4cdf598859a62bab46c
SHA1: 353207375b17960c1148736e2f3e2ab8888ec917
package dev.vality.disputes.provider.payments.service;

import dev.vality.damsel.domain.InvoicePaymentAdjustment;
import dev.vality.damsel.domain.InvoicePaymentStatus;
import dev.vality.damsel.payment_processing.InvoicePayment;
import dev.vality.disputes.domain.tables.pojos.ProviderCallback;
import lombok.RequiredArgsConstructor;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

@Component
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ProviderPaymentsAdjustmentExtractor {

    public static final String PROVIDER_PAYMENT_MASK = "providerCallbackId=%s";

    public String getReason(ProviderCallback providerCallback) {
        return Optional.ofNullable(providerCallback.getApproveReason())
                .map(s -> String.format(PROVIDER_PAYMENT_MASK + ", reason=%s", providerCallback.getId(), s))
                .orElse(String.format(PROVIDER_PAYMENT_MASK, providerCallback.getId()));
    }

    public boolean isCashFlowAdjustmentByProviderPaymentsExist(InvoicePayment invoicePayment, ProviderCallback providerCallback) {
        return getInvoicePaymentAdjustmentStream(invoicePayment)
                .filter(adj -> isProviderPaymentsAdjustment(adj.getReason(), providerCallback))
                .anyMatch(adj -> adj.getState() != null && adj.getState().isSetCashFlow());
    }

    public boolean isCapturedAdjustmentByProviderPaymentsExist(InvoicePayment invoicePayment, ProviderCallback providerCallback) {
        return getInvoicePaymentAdjustmentStream(invoicePayment)
                .filter(adj -> isProviderPaymentsAdjustment(adj.getReason(), providerCallback))
                .filter(adj -> adj.getState() != null && adj.getState().isSetStatusChange())
                .filter(adj -> getTargetStatus(adj).isSetCaptured())
                .anyMatch(adj -> isProviderPaymentsAdjustment(getTargetStatus(adj).getCaptured().getReason(), providerCallback));
    }

    private Stream<InvoicePaymentAdjustment> getInvoicePaymentAdjustmentStream(InvoicePayment invoicePayment) {
        return Optional.ofNullable(invoicePayment.getAdjustments())
                .orElse(List.of())
                .stream();
    }

    private InvoicePaymentStatus getTargetStatus(InvoicePaymentAdjustment s) {
        return s.getState().getStatusChange().getScenario().getTargetStatus();
    }

    private boolean isProviderPaymentsAdjustment(String reason, ProviderCallback providerCallback) {
        return !StringUtils.isBlank(reason)
                && reason.equalsIgnoreCase(getReason(providerCallback));
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/service/ProviderPaymentsRouting.java
MD5:  65f54ba5cd04064051c701f949260dbd
SHA1: acb3008ee7ba294946051d1edb069c67e207ecc0
package dev.vality.disputes.provider.payments.service;

import dev.vality.disputes.exception.RoutingException;
import dev.vality.disputes.schedule.model.ProviderData;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.util.ObjectUtils;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProviderPaymentsRouting {

    private static final String PAYMENTS_URL_POSTFIX_DEFAULT = "provider-payments";
    private static final String OPTION_PROVIDER_PAYMENTS_URL_FIELD_NAME = "provider_payments_url";

    public void initRouteUrl(ProviderData providerData) {
        var url = providerData.getOptions().get(OPTION_PROVIDER_PAYMENTS_URL_FIELD_NAME);
        if (ObjectUtils.isEmpty(url)) {
            url = createDefaultRouteUrl(providerData.getDefaultProviderUrl());
        }
        providerData.setRouteUrl(url);
    }

    private String createDefaultRouteUrl(String defaultProviderUrl) {
        try {
            return UriComponentsBuilder.fromUri(URI.create(defaultProviderUrl))
                    .pathSegment(PAYMENTS_URL_POSTFIX_DEFAULT)
                    .encode()
                    .build()
                    .toUriString();
        } catch (Throwable ex) {
            throw new RoutingException("Unable to create default provider url: ", ex);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/service/ProviderPaymentsService.java
MD5:  85aaada4bccf31e123367017b1eb4ac9
SHA1: 857c62d7ffa883c2a0dea0df3f0e40360872659e
package dev.vality.disputes.provider.payments.service;

import dev.vality.damsel.domain.Currency;
import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.damsel.payment_processing.InvoicePayment;
import dev.vality.disputes.constant.ErrorMessage;
import dev.vality.disputes.domain.enums.ProviderPaymentsStatus;
import dev.vality.disputes.domain.tables.pojos.ProviderCallback;
import dev.vality.disputes.exception.CapturedPaymentException;
import dev.vality.disputes.exception.InvoicingPaymentStatusRestrictionsException;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.provider.payments.client.ProviderPaymentsRemoteClient;
import dev.vality.disputes.provider.payments.converter.ProviderPaymentsToInvoicePaymentCapturedAdjustmentParamsConverter;
import dev.vality.disputes.provider.payments.converter.ProviderPaymentsToInvoicePaymentCashFlowAdjustmentParamsConverter;
import dev.vality.disputes.provider.payments.converter.TransactionContextConverter;
import dev.vality.disputes.provider.payments.dao.ProviderCallbackDao;
import dev.vality.disputes.provider.payments.exception.ProviderCallbackAlreadyExistException;
import dev.vality.disputes.provider.payments.exception.ProviderCallbackStatusWasUpdatedByAnotherThreadException;
import dev.vality.disputes.provider.payments.exception.ProviderPaymentsUnexpectedPaymentStatus;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.disputes.schedule.service.ProviderDataService;
import dev.vality.disputes.service.DisputesService;
import dev.vality.disputes.service.external.InvoicingService;
import dev.vality.disputes.util.PaymentAmountUtil;
import dev.vality.disputes.util.PaymentStatusValidator;
import dev.vality.provider.payments.PaymentStatusResult;
import dev.vality.provider.payments.ProviderPaymentsCallbackParams;
import dev.vality.provider.payments.TransactionContext;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Objects;
import java.util.Optional;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ProviderPaymentsService {

    private final ProviderCallbackDao providerCallbackDao;
    private final InvoicingService invoicingService;
    private final TransactionContextConverter transactionContextConverter;
    private final ProviderPaymentsToInvoicePaymentCapturedAdjustmentParamsConverter providerPaymentsToInvoicePaymentCapturedAdjustmentParamsConverter;
    private final ProviderPaymentsToInvoicePaymentCashFlowAdjustmentParamsConverter providerPaymentsToInvoicePaymentCashFlowAdjustmentParamsConverter;
    private final ProviderPaymentsAdjustmentExtractor providerPaymentsAdjustmentExtractor;
    private final ProviderDataService providerDataService;
    private final DisputesService disputesService;
    private final ProviderPaymentsRemoteClient providerPaymentsRemoteClient;

    @Async("disputesAsyncServiceExecutor")
    public void processCallback(ProviderPaymentsCallbackParams callback) {
        try {
            var invoiceId = callback.getInvoiceId().get();
            var paymentId = callback.getPaymentId().get();
            var invoicePayment = invoicingService.getInvoicePayment(invoiceId, paymentId);
            log.debug("Got invoicePayment {}", callback);
            // validate
            PaymentStatusValidator.checkStatus(invoicePayment);
            // validate
            var providerTrxId = getProviderTrxId(invoicePayment);
            var providerData = providerDataService.getProviderData(invoicePayment.getRoute().getProvider(), invoicePayment.getRoute().getTerminal());
            var transactionContext = transactionContextConverter.convert(invoiceId, paymentId, providerTrxId, providerData, invoicePayment.getLastTransactionInfo());
            var currency = providerDataService.getCurrency(invoicePayment.getPayment().getCost().getCurrency());
            var invoiceAmount = invoicePayment.getPayment().getCost().getAmount();
            checkPaymentStatusAndSave(transactionContext, currency, providerData, invoiceAmount);
        } catch (InvoicingPaymentStatusRestrictionsException ex) {
            log.info("InvoicingPaymentStatusRestrictionsException when process ProviderPaymentsCallbackParams {}", callback);
        } catch (NotFoundException ex) {
            log.warn("NotFound when handle ProviderPaymentsCallbackParams, type={}", ex.getType(), ex);
        } catch (Throwable ex) {
            log.warn("Failed to handle ProviderPaymentsCallbackParams", ex);
        }
    }

    @Transactional
    public void checkPaymentStatusAndSave(TransactionContext transactionContext, Currency currency, ProviderData providerData, long amount) {
        checkProviderCallbackExist(transactionContext.getInvoiceId(), transactionContext.getPaymentId());
        var paymentStatusResult = providerPaymentsRemoteClient.checkPaymentStatus(transactionContext, currency, providerData);
        if (paymentStatusResult.isSuccess()) {
            var providerCallback = new ProviderCallback();
            providerCallback.setInvoiceId(transactionContext.getInvoiceId());
            providerCallback.setPaymentId(transactionContext.getPaymentId());
            providerCallback.setChangedAmount(getChangedAmount(amount, paymentStatusResult));
            providerCallback.setAmount(amount);
            log.info("Save providerCallback {}", providerCallback);
            providerCallbackDao.save(providerCallback);
        } else {
            throw new ProviderPaymentsUnexpectedPaymentStatus(
                    "providerPaymentsService.checkPaymentStatusAndSave unsuccessful: Cant do createAdjustment");
        }
    }

    @Transactional
    public List<ProviderCallback> getPaymentsForHgCall(int batchSize) {
        var locked = providerCallbackDao.getProviderCallbacksForHgCall(batchSize);
        if (!locked.isEmpty()) {
            log.debug("getProviderCallbackForHgCall has been found, size={}", locked.size());
        }
        return locked;
    }

    @Transactional
    public void callHgForCreateAdjustment(ProviderCallback providerCallback) {
        try {
            // validate
            checkCreateAdjustmentStatus(providerCallback);
            // validate
            var invoicePayment = invoicingService.getInvoicePayment(providerCallback.getInvoiceId(), providerCallback.getPaymentId());
            // validate
            PaymentStatusValidator.checkStatus(invoicePayment);
            if (createCashFlowAdjustment(providerCallback, invoicePayment)) {
                // pause for waiting finish createCashFlowAdjustment
                return;
            }
            createCapturedAdjustment(providerCallback, invoicePayment);
            finishSucceeded(providerCallback);
        } catch (NotFoundException ex) {
            log.error("NotFound when handle ProviderPaymentsService.callHgForCreateAdjustment, type={}", ex.getType(), ex);
            switch (ex.getType()) {
                case INVOICE -> finishFailed(providerCallback, ErrorMessage.INVOICE_NOT_FOUND);
                case PAYMENT -> finishFailed(providerCallback, ErrorMessage.PAYMENT_NOT_FOUND);
                case PROVIDERCALLBACK -> log.debug("ProviderCallback locked {}", providerCallback);
                default -> throw ex;
            }
        } catch (CapturedPaymentException ex) {
            log.warn("CapturedPaymentException when handle ProviderPaymentsService.callHgForCreateAdjustment", ex);
            var changedAmount = PaymentAmountUtil.getChangedAmount(ex.getInvoicePayment().getPayment());
            if (changedAmount != null) {
                providerCallback.setChangedAmount(changedAmount);
            }
            finishSucceeded(providerCallback);
        } catch (InvoicingPaymentStatusRestrictionsException ex) {
            log.error("InvoicingPaymentRestrictionStatus when handle ProviderPaymentsService.callHgForCreateAdjustment", ex);
            finishFailed(providerCallback, PaymentStatusValidator.getInvoicingPaymentStatusRestrictionsErrorReason(ex));
        } catch (ProviderCallbackStatusWasUpdatedByAnotherThreadException ex) {
            log.debug("ProviderCallbackStatusWasUpdatedByAnotherThread when handle ProviderPaymentsService.callHgForCreateAdjustment", ex);
        }
    }

    public void finishSucceeded(ProviderCallback providerCallback) {
        log.info("Trying to set succeeded ProviderCallback status {}", providerCallback);
        providerCallback.setStatus(ProviderPaymentsStatus.succeeded);
        providerCallbackDao.update(providerCallback);
        log.debug("ProviderCallback status has been set to succeeded {}", providerCallback.getInvoiceId());
        disputeFinishSucceeded(providerCallback);
    }

    public void finishFailed(ProviderCallback providerCallback, String errorReason) {
        log.warn("Trying to set failed ProviderCallback status with '{}' errorReason, {}", errorReason, providerCallback.getInvoiceId());
        if (errorReason != null) {
            providerCallback.setErrorReason(errorReason);
        }
        providerCallback.setStatus(ProviderPaymentsStatus.failed);
        providerCallbackDao.update(providerCallback);
        log.debug("ProviderCallback status has been set to failed {}", providerCallback.getInvoiceId());
        disputeFinishFailed(providerCallback, errorReason);
    }

    private String getProviderTrxId(InvoicePayment payment) {
        return Optional.ofNullable(payment.getLastTransactionInfo())
                .map(TransactionInfo::getId)
                .orElseThrow(() -> new NotFoundException(
                        String.format("Payment with id: %s and filled ProviderTrxId not found!", payment.getPayment().getId()), NotFoundException.Type.PROVIDERTRXID));
    }

    private Long getChangedAmount(long amount, PaymentStatusResult paymentStatusResult) {
        return paymentStatusResult.getChangedAmount()
                .filter(changedAmount -> changedAmount != amount)
                .orElse(null);
    }

    private void checkCreateAdjustmentStatus(ProviderCallback providerCallback) {
        var forUpdate = providerCallbackDao.getProviderCallbackForUpdateSkipLocked(providerCallback.getId());
        if (forUpdate.getStatus() != ProviderPaymentsStatus.create_adjustment) {
            throw new ProviderCallbackStatusWasUpdatedByAnotherThreadException();
        }
    }

    private boolean createCashFlowAdjustment(ProviderCallback providerCallback, InvoicePayment invoicePayment) {
        if (!providerPaymentsAdjustmentExtractor.isCashFlowAdjustmentByProviderPaymentsExist(invoicePayment, providerCallback)
                && (providerCallback.getAmount() != null
                && providerCallback.getChangedAmount() != null
                && !Objects.equals(providerCallback.getAmount(), providerCallback.getChangedAmount()))) {
            var cashFlowParams = providerPaymentsToInvoicePaymentCashFlowAdjustmentParamsConverter.convert(providerCallback);
            invoicingService.createPaymentAdjustment(providerCallback.getInvoiceId(), providerCallback.getPaymentId(), cashFlowParams);
            return true;
        } else {
            log.info("Creating CashFlowAdjustment was skipped {}", providerCallback);
            return false;
        }
    }

    private void createCapturedAdjustment(ProviderCallback providerCallback, InvoicePayment invoicePayment) {
        if (!providerPaymentsAdjustmentExtractor.isCapturedAdjustmentByProviderPaymentsExist(invoicePayment, providerCallback)) {
            var capturedParams = providerPaymentsToInvoicePaymentCapturedAdjustmentParamsConverter.convert(providerCallback);
            invoicingService.createPaymentAdjustment(providerCallback.getInvoiceId(), providerCallback.getPaymentId(), capturedParams);
        } else {
            log.info("Creating CapturedAdjustment was skipped {}", providerCallback);
        }
    }

    private void disputeFinishSucceeded(ProviderCallback providerCallback) {
        try {
            disputesService.finishSucceeded(providerCallback.getInvoiceId(), providerCallback.getPaymentId(), providerCallback.getChangedAmount());
        } catch (NotFoundException ex) {
            log.debug("NotFound when handle disputeFinishSucceeded, type={}", ex.getType(), ex);
        } catch (Throwable ex) {
            log.error("Received exception while ProviderPaymentsService.disputeFinishSucceeded", ex);
        }
    }

    private void disputeFinishFailed(ProviderCallback providerCallback, String errorMessage) {
        try {
            disputesService.finishFailed(providerCallback.getInvoiceId(), providerCallback.getPaymentId(), errorMessage);
        } catch (NotFoundException ex) {
            log.debug("NotFound when handle disputeFinishFailed, type={}", ex.getType(), ex);
        } catch (Throwable ex) {
            log.error("Received exception while ProviderPaymentsService.disputeFinishSucceeded", ex);
        }
    }

    private void checkProviderCallbackExist(String invoiceId, String paymentId) {
        try {
            var providerCallback = providerCallbackDao.get(invoiceId, paymentId);
            log.debug("ProviderCallback exist {}", providerCallback);
            throw new ProviderCallbackAlreadyExistException();
        } catch (NotFoundException ignored) {
            log.debug("It's new provider callback");
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/service/ProviderPaymentsThriftInterfaceBuilder.java
MD5:  baece3da5da72a87025b1f0200d09625
SHA1: b12d82dc25be65b145ad7116c68a64659ee6fa10
package dev.vality.disputes.provider.payments.service;

import dev.vality.disputes.config.properties.AdaptersConnectionProperties;
import dev.vality.provider.payments.ProviderPaymentsServiceSrv;
import dev.vality.woody.thrift.impl.http.THSpawnClientBuilder;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.util.concurrent.TimeUnit;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ProviderPaymentsThriftInterfaceBuilder {

    private final AdaptersConnectionProperties adaptersConnectionProperties;

    @Cacheable(value = "providerPayments", key = "#root.args[0]", cacheManager = "providerPaymentsCacheManager")
    public ProviderPaymentsServiceSrv.Iface buildWoodyClient(String routeUrl) {
        log.info("Creating new client for url: {}", routeUrl);
        return new THSpawnClientBuilder()
                .withNetworkTimeout((int) TimeUnit.SECONDS.toMillis(adaptersConnectionProperties.getTimeoutSec()))
                .withAddress(URI.create(routeUrl))
                .build(ProviderPaymentsServiceSrv.Iface.class);
    }
}


FILE: ./src/main/java/dev/vality/disputes/provider/payments/servlet/ProviderPaymentsCallbackServlet.java
MD5:  72d012d40aac646f78289048e65c89ef
SHA1: 102af9b320a66a8bb4111446e0e08f8d42e72b07
package dev.vality.disputes.provider.payments.servlet;

import dev.vality.provider.payments.ProviderPaymentsCallbackServiceSrv;
import dev.vality.woody.thrift.impl.http.THServiceBuilder;
import jakarta.servlet.*;
import jakarta.servlet.annotation.WebServlet;
import org.springframework.beans.factory.annotation.Autowired;

import java.io.IOException;

@WebServlet("/v1/callback")
public class ProviderPaymentsCallbackServlet extends GenericServlet {

    @Autowired
    private ProviderPaymentsCallbackServiceSrv.Iface providerPaymentsCallbackHandler;

    private Servlet servlet;

    @Override
    public void init(ServletConfig config) throws ServletException {
        super.init(config);
        servlet = new THServiceBuilder()
                .build(ProviderPaymentsCallbackServiceSrv.Iface.class, providerPaymentsCallbackHandler);
    }

    @Override
    public void service(ServletRequest request, ServletResponse response) throws ServletException, IOException {
        servlet.service(request, response);
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/CreatedDisputesTask.java
MD5:  c83f4c9d823cac1b42c2d5432394721a
SHA1: 95bba8f6a600d1475b45c69fe8dba9b1626fac25
package dev.vality.disputes.schedule;

import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.schedule.core.CreatedDisputesService;
import dev.vality.disputes.schedule.handler.CreatedDisputeHandler;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.stream.Collectors;

@Slf4j
@ConditionalOnProperty(value = "dispute.isScheduleCreatedEnabled", havingValue = "true")
@Service
@RequiredArgsConstructor
public class CreatedDisputesTask {

    private final ExecutorService disputesThreadPool;
    private final CreatedDisputesService createdDisputesService;

    @Value("${dispute.batchSize}")
    private int batchSize;

    @Scheduled(fixedDelayString = "${dispute.fixedDelayCreated}", initialDelayString = "${dispute.initialDelayCreated}")
    public void processCreated() {
        try {
            var disputes = createdDisputesService.getCreatedSkipLocked(batchSize);
            var callables = disputes.stream()
                    .map(this::handleCreated)
                    .collect(Collectors.toList());
            disputesThreadPool.invokeAll(callables);
        } catch (InterruptedException ex) {
            log.error("Received InterruptedException while thread executed report", ex);
            Thread.currentThread().interrupt();
        } catch (Throwable ex) {
            log.error("Received exception while scheduler processed created disputes", ex);
        }
    }

    private Callable<UUID> handleCreated(Dispute dispute) {
        return () -> new CreatedDisputeHandler(createdDisputesService).handle(dispute);
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/ForgottenDisputesTask.java
MD5:  8511dfbf56a3a059a0c2fed43f581684
SHA1: dd9003b300c15e4bf6390cc400509c32e421c8c1
package dev.vality.disputes.schedule;

import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.schedule.core.ForgottenDisputesService;
import dev.vality.disputes.schedule.handler.ForgottenDisputeHandler;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.stream.Collectors;

@Slf4j
@ConditionalOnProperty(value = "dispute.isScheduleForgottenEnabled", havingValue = "true")
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ForgottenDisputesTask {

    private final ForgottenDisputesService forgottenDisputesService;
    private final ExecutorService disputesThreadPool;

    @Value("${dispute.batchSize}")
    private int batchSize;

    @Scheduled(fixedDelayString = "${dispute.fixedDelayForgotten}", initialDelayString = "${dispute.initialDelayForgotten}")
    public void processForgottenDisputes() {
        try {
            var disputes = forgottenDisputesService.getForgottenSkipLocked(batchSize);
            var callables = disputes.stream()
                    .map(this::handleForgotten)
                    .collect(Collectors.toList());
            disputesThreadPool.invokeAll(callables);
        } catch (InterruptedException ex) {
            log.error("Received InterruptedException while thread executed report", ex);
            Thread.currentThread().interrupt();
        } catch (Throwable ex) {
            log.error("Received exception while scheduler processed Forgotten disputes", ex);
        }
    }

    private Callable<UUID> handleForgotten(Dispute dispute) {
        return () -> new ForgottenDisputeHandler(forgottenDisputesService).handle(dispute);
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/NotificationTask.java
MD5:  53ce28a61f176fc8bc9a088290fbfa67
SHA1: 72ac6da32235c47dedea1f8f6fcfb22cd090869f
package dev.vality.disputes.schedule;

import dev.vality.disputes.schedule.core.NotificationService;
import dev.vality.disputes.schedule.handler.NotificationHandler;
import dev.vality.swag.disputes.model.NotifyRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.stream.Collectors;

@Slf4j
@ConditionalOnProperty(value = "dispute.isScheduleNotificationEnabled", havingValue = "true")
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class NotificationTask {

    private final ExecutorService disputesThreadPool;
    private final NotificationService notificationService;

    @Value("${dispute.batchSize}")
    private int batchSize;

    @Scheduled(fixedDelayString = "${dispute.fixedDelayNotification}", initialDelayString = "${dispute.initialDelayNotification}")
    public void processNotifications() {
        try {
            var notifications = notificationService.getNotifyRequests(batchSize);
            var callables = notifications.stream()
                    .map(this::handleNotification)
                    .collect(Collectors.toList());
            disputesThreadPool.invokeAll(callables);
        } catch (InterruptedException ex) {
            log.error("Received InterruptedException while thread executed report", ex);
            Thread.currentThread().interrupt();
        } catch (Throwable ex) {
            log.error("Received exception while scheduler processed notifications", ex);
        }
    }

    private Callable<String> handleNotification(NotifyRequest notifyRequest) {
        return () -> new NotificationHandler(notificationService).handle(notifyRequest);
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/PendingDisputesTask.java
MD5:  b3a9b454bf09bf1307ed6f3f0a7ffdde
SHA1: 36b907f2f526760b672ea8b4a111497f1a5f351b
package dev.vality.disputes.schedule;

import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.schedule.core.PendingDisputesService;
import dev.vality.disputes.schedule.handler.PendingDisputeHandler;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.stream.Collectors;

@Slf4j
@ConditionalOnProperty(value = "dispute.isSchedulePendingEnabled", havingValue = "true")
@Service
@RequiredArgsConstructor
public class PendingDisputesTask {

    private final ExecutorService disputesThreadPool;
    private final PendingDisputesService pendingDisputesService;

    @Value("${dispute.batchSize}")
    private int batchSize;

    @Scheduled(fixedDelayString = "${dispute.fixedDelayPending}", initialDelayString = "${dispute.initialDelayPending}")
    public void processPending() {
        try {
            var disputes = pendingDisputesService.getPendingSkipLocked(batchSize);
            var callables = disputes.stream()
                    .map(this::handlePending)
                    .collect(Collectors.toList());
            disputesThreadPool.invokeAll(callables);
        } catch (InterruptedException ex) {
            log.error("Received InterruptedException while thread executed report", ex);
            Thread.currentThread().interrupt();
        } catch (Throwable ex) {
            log.error("Received exception while scheduler processed pending disputes", ex);
        }
    }

    private Callable<UUID> handlePending(Dispute dispute) {
        return () -> new PendingDisputeHandler(pendingDisputesService).handle(dispute);
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/catcher/WoodyRuntimeExceptionCatcher.java
MD5:  5f2ab92b0afa8b2d8e896dab8f1b718b
SHA1: 5a0726ad76945d58fd6fb9a7b035d599e3fa8b9f
package dev.vality.disputes.schedule.catcher;

import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.disputes.schedule.service.ExternalGatewayChecker;
import dev.vality.woody.api.flow.error.WRuntimeException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.function.Consumer;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class WoodyRuntimeExceptionCatcher {

    private final ExternalGatewayChecker externalGatewayChecker;

    public void catchProviderDisputesApiNotExist(ProviderData providerData, Runnable runnable, Runnable defaultRemoteClientRunnable) {
        try {
            runnable.run();
        } catch (WRuntimeException ex) {
            if (externalGatewayChecker.isProviderDisputesApiNotExist(providerData, ex)) {
                log.info("Trying to call defaultRemoteClient.createDispute() by case remoteClient.createDispute()==404", ex);
                defaultRemoteClientRunnable.run();
                return;
            }
            throw ex;
        }
    }

    public void catchUnexpectedResultMapping(Runnable runnable, Consumer<WRuntimeException> unexpectedResultMappingHandler) {
        try {
            runnable.run();
        } catch (WRuntimeException ex) {
            if (externalGatewayChecker.isProviderDisputesUnexpectedResultMapping(ex)) {
                unexpectedResultMappingHandler.accept(ex);
                return;
            }
            throw ex;
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/client/DefaultRemoteClient.java
MD5:  dc6fc8805b545532e0589fc367b47ac6
SHA1: 22dd1327c9da89984edf1be79c648de4b05124e6
package dev.vality.disputes.schedule.client;

import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.provider.Attachment;
import dev.vality.disputes.provider.DisputeCreatedResult;
import dev.vality.disputes.schedule.model.ProviderData;

import java.util.List;

@SuppressWarnings({"LineLength"})
public interface DefaultRemoteClient {

    Boolean routeUrlEquals(ProviderData providerData);

    DisputeCreatedResult createDispute(Dispute dispute, List<Attachment> attachments, ProviderData providerData, TransactionInfo transactionInfo);

}


FILE: ./src/main/java/dev/vality/disputes/schedule/client/DisputesTgBotRemoteClientImpl.java
MD5:  055d96744cb8260ca2b8c184b2e57e60
SHA1: 32cc3371166561b02fd8561cd878acc4fa274f6a
package dev.vality.disputes.schedule.client;

import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.provider.Attachment;
import dev.vality.disputes.provider.DisputeCreatedResult;
import dev.vality.disputes.schedule.converter.DisputeParamsConverter;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.disputes.service.external.DisputesTgBotService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.List;

@Slf4j
@Service
@ConditionalOnProperty(value = "service.disputes-tg-bot.provider.enabled", havingValue = "true", matchIfMissing = true)
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class DisputesTgBotRemoteClientImpl implements DefaultRemoteClient {

    private final DisputesTgBotService disputesTgBotService;
    private final DisputeParamsConverter disputeParamsConverter;

    @Value("${service.disputes-tg-bot.provider.url}")
    private String routeUrl;

    @Override
    public Boolean routeUrlEquals(ProviderData providerData) {
        return StringUtils.equalsIgnoreCase(providerData.getRouteUrl(), routeUrl);
    }

    @Override
    public DisputeCreatedResult createDispute(Dispute dispute, List<Attachment> attachments, ProviderData providerData, TransactionInfo transactionInfo) {
        log.info("Trying to call disputesTgBotService.createDispute() {}", dispute.getId());
        var disputeParams = disputeParamsConverter.convert(dispute, attachments, providerData.getOptions(), transactionInfo);
        providerData.setRouteUrl(routeUrl);
        log.debug("Trying to disputesTgBotService.createDispute() call {}", dispute.getId());
        var result = disputesTgBotService.createDispute(disputeParams);
        log.debug("disputesTgBotService.createDispute() has been called {} {}", dispute.getId(), result);
        return result;
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/client/DummyRemoteClientImpl.java
MD5:  dc79fe81466fd74799e0e5483b9028a1
SHA1: 18dd59460dcc60c456380ce90113e827004ba87e
package dev.vality.disputes.schedule.client;

import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.provider.Attachment;
import dev.vality.disputes.provider.DisputeCreatedResult;
import dev.vality.disputes.provider.DisputeCreatedSuccessResult;
import dev.vality.disputes.schedule.model.ProviderData;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.UUID;

@Slf4j
@Service
@ConditionalOnProperty(value = "service.disputes-tg-bot.provider.enabled", havingValue = "false")
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class DummyRemoteClientImpl implements DefaultRemoteClient {

    private final String routeUrl = "tg-bot";

    @Override
    public Boolean routeUrlEquals(ProviderData providerData) {
        return StringUtils.equalsIgnoreCase(providerData.getRouteUrl(), routeUrl);
    }

    @Override
    public DisputeCreatedResult createDispute(Dispute dispute, List<Attachment> attachments, ProviderData providerData, TransactionInfo transactionInfo) {
        log.debug("Trying to call DummyRemoteClientImpl.createDispute() {}", dispute.getId());
        providerData.setRouteUrl(routeUrl);
        return DisputeCreatedResult.successResult(new DisputeCreatedSuccessResult(UUID.randomUUID().toString()));
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/client/RemoteClient.java
MD5:  345208d4deb3fed058ac5fa675226bbf
SHA1: c77469811ec42da96dea706c8803cd9090ed253e
package dev.vality.disputes.schedule.client;

import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.domain.tables.pojos.ProviderDispute;
import dev.vality.disputes.provider.Attachment;
import dev.vality.disputes.provider.DisputeCreatedResult;
import dev.vality.disputes.provider.DisputeStatusResult;
import dev.vality.disputes.schedule.converter.DisputeContextConverter;
import dev.vality.disputes.schedule.converter.DisputeParamsConverter;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.disputes.schedule.service.ProviderDisputesRouting;
import dev.vality.disputes.schedule.service.ProviderDisputesThriftInterfaceBuilder;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class RemoteClient {

    private final ProviderDisputesRouting providerDisputesRouting;
    private final ProviderDisputesThriftInterfaceBuilder providerDisputesThriftInterfaceBuilder;
    private final DisputeParamsConverter disputeParamsConverter;
    private final DisputeContextConverter disputeContextConverter;

    @SneakyThrows
    public DisputeCreatedResult createDispute(Dispute dispute, List<Attachment> attachments, ProviderData providerData, TransactionInfo transactionInfo) {
        providerDisputesRouting.initRouteUrl(providerData);
        log.info("Trying to call ProviderDisputesThriftInterfaceBuilder.createDispute() {}", dispute.getId());
        var remoteClient = providerDisputesThriftInterfaceBuilder.buildWoodyClient(providerData.getRouteUrl());
        log.debug("Trying to build disputeParams {}", dispute.getId());
        var disputeParams = disputeParamsConverter.convert(dispute, attachments, providerData.getOptions(), transactionInfo);
        log.debug("Trying to routed remote provider's createDispute() call {}", dispute.getId());
        var result = remoteClient.createDispute(disputeParams);
        log.debug("Routed remote provider's createDispute() has been called {} {}", dispute.getId(), result);
        return result;
    }

    @SneakyThrows
    public DisputeStatusResult checkDisputeStatus(Dispute dispute, ProviderDispute providerDispute, ProviderData providerData, TransactionInfo transactionInfo) {
        providerDisputesRouting.initRouteUrl(providerData);
        log.info("Trying to call ProviderDisputesThriftInterfaceBuilder.checkDisputeStatus() {}", dispute.getId());
        var remoteClient = providerDisputesThriftInterfaceBuilder.buildWoodyClient(providerData.getRouteUrl());
        log.debug("Trying to build disputeContext {}", dispute.getId());
        var disputeContext = disputeContextConverter.convert(dispute, providerDispute, providerData.getOptions(), transactionInfo);
        log.debug("Trying to routed remote provider's checkDisputeStatus() call {}", dispute.getId());
        var result = remoteClient.checkDisputeStatus(disputeContext);
        log.debug("Routed remote provider's checkDisputeStatus() has been called {} {}", dispute.getId(), result);
        return result;
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/converter/DisputeContextConverter.java
MD5:  db5d23bc38c10f22a7e9c33ac9f44cbf
SHA1: 57def95f36556ff438a99032ad80eb96a9d54984
package dev.vality.disputes.schedule.converter;

import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.domain.tables.pojos.ProviderDispute;
import dev.vality.disputes.provider.DisputeContext;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Map;

@Component
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class DisputeContextConverter {

    private final DisputeCurrencyConverter disputeCurrencyConverter;

    public DisputeContext convert(Dispute dispute, ProviderDispute providerDispute, Map<String, String> options, TransactionInfo transactionInfo) {
        var disputeContext = new DisputeContext();
        disputeContext.setProviderDisputeId(providerDispute.getProviderDisputeId());
        var currency = disputeCurrencyConverter.convert(dispute);
        disputeContext.setCurrency(currency);
        disputeContext.setTerminalOptions(options);
        disputeContext.setTransactionInfo(transactionInfo);
        return disputeContext;
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/converter/DisputeCurrencyConverter.java
MD5:  fd67fe0ecb8be71b7a68c5abab050c31
SHA1: fd25bec0174123b123b13d0f0c738d6054fde3fd
package dev.vality.disputes.schedule.converter;

import dev.vality.damsel.domain.Currency;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import org.springframework.stereotype.Component;

@Component
public class DisputeCurrencyConverter {

    public Currency convert(Dispute dispute) {
        var currency = new Currency();
        currency.setName(dispute.getCurrencyName());
        currency.setSymbolicCode(dispute.getCurrencySymbolicCode());
        currency.setNumericCode(dispute.getCurrencyNumericCode().shortValue());
        currency.setExponent(dispute.getCurrencyExponent().shortValue());
        return currency;
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/converter/DisputeParamsConverter.java
MD5:  957cb2fed638e14cd176a64cc7064471
SHA1: 3761d7bf0b0cec1240f833db0d657479de31cba0
package dev.vality.disputes.schedule.converter;

import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.provider.Attachment;
import dev.vality.disputes.provider.Cash;
import dev.vality.disputes.provider.DisputeParams;
import dev.vality.disputes.provider.TransactionContext;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

@Component
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class DisputeParamsConverter {

    private final DisputeCurrencyConverter disputeCurrencyConverter;

    public DisputeParams convert(Dispute dispute, List<Attachment> attachments, Map<String, String> terminalOptions, TransactionInfo transactionInfo) {
        var disputeParams = new DisputeParams();
        disputeParams.setAttachments(attachments);
        var transactionContext = new TransactionContext();
        transactionContext.setProviderTrxId(dispute.getProviderTrxId());
        transactionContext.setInvoiceId(dispute.getInvoiceId());
        transactionContext.setPaymentId(dispute.getPaymentId());
        transactionContext.setTerminalOptions(terminalOptions);
        transactionContext.setTransactionInfo(transactionInfo);
        disputeParams.setTransactionContext(transactionContext);
        if (dispute.getAmount() != null) {
            var cash = new Cash();
            cash.setAmount(dispute.getAmount());
            var currency = disputeCurrencyConverter.convert(dispute);
            cash.setCurrency(currency);
            disputeParams.setCash(cash);
        }
        disputeParams.setReason(dispute.getReason());
        disputeParams.setDisputeId(dispute.getId().toString());
        return disputeParams;
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/core/CreatedDisputesService.java
MD5:  ac6304578279ae0ee9ed01a3fa7cb5ab
SHA1: 7661f4d2f1d1f5499a94d27b28cbbaf6afa214bc
package dev.vality.disputes.schedule.core;

import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.disputes.constant.ErrorMessage;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.exception.CapturedPaymentException;
import dev.vality.disputes.exception.DisputeStatusWasUpdatedByAnotherThreadException;
import dev.vality.disputes.exception.InvoicingPaymentStatusRestrictionsException;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.provider.DisputeCreatedResult;
import dev.vality.disputes.provider.DisputeStatusResult;
import dev.vality.disputes.provider.DisputeStatusSuccessResult;
import dev.vality.disputes.provider.payments.client.ProviderPaymentsRemoteClient;
import dev.vality.disputes.provider.payments.converter.TransactionContextConverter;
import dev.vality.disputes.schedule.catcher.WoodyRuntimeExceptionCatcher;
import dev.vality.disputes.schedule.client.DefaultRemoteClient;
import dev.vality.disputes.schedule.client.RemoteClient;
import dev.vality.disputes.schedule.converter.DisputeCurrencyConverter;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.disputes.schedule.result.DisputeCreateResultHandler;
import dev.vality.disputes.schedule.result.DisputeStatusResultHandler;
import dev.vality.disputes.schedule.service.AttachmentsService;
import dev.vality.disputes.schedule.service.ProviderDataService;
import dev.vality.disputes.service.DisputesService;
import dev.vality.disputes.service.external.InvoicingService;
import dev.vality.disputes.util.PaymentStatusValidator;
import dev.vality.provider.payments.PaymentStatusResult;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;
import java.util.function.Consumer;

import static dev.vality.disputes.constant.TerminalOptionsField.DISPUTE_FLOW_PROVIDERS_API_EXIST;
import static dev.vality.disputes.util.PaymentAmountUtil.getChangedAmount;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class CreatedDisputesService {

    private final RemoteClient remoteClient;
    private final DisputesService disputesService;
    private final AttachmentsService attachmentsService;
    private final InvoicingService invoicingService;
    private final ProviderDataService providerDataService;
    private final TransactionContextConverter transactionContextConverter;
    private final DisputeCurrencyConverter disputeCurrencyConverter;
    private final DefaultRemoteClient defaultRemoteClient;
    private final ProviderPaymentsRemoteClient providerPaymentsRemoteClient;
    private final DisputeCreateResultHandler disputeCreateResultHandler;
    private final DisputeStatusResultHandler disputeStatusResultHandler;
    private final WoodyRuntimeExceptionCatcher woodyRuntimeExceptionCatcher;

    @Transactional
    public List<Dispute> getCreatedSkipLocked(int batchSize) {
        return disputesService.getCreatedSkipLocked(batchSize);
    }

    @Transactional
    public void callCreateDisputeRemotely(Dispute dispute) {
        try {
            // validate
            disputesService.checkCreatedStatus(dispute);
            // validate
            var invoicePayment = invoicingService.getInvoicePayment(dispute.getInvoiceId(), dispute.getPaymentId());
            // validate
            PaymentStatusValidator.checkStatus(invoicePayment);
            var providerData = providerDataService.getProviderData(dispute.getProviderId(), dispute.getTerminalId());
            var providerStatus = checkProviderPaymentStatus(dispute, providerData, invoicePayment.getLastTransactionInfo());
            if (providerStatus.isSuccess()) {
                handleSucceededResultWithCreateAdjustment(dispute, providerStatus, providerData, invoicePayment.getLastTransactionInfo());
                return;
            }
            var finishCreateDisputeResult = (Consumer<DisputeCreatedResult>) result -> {
                switch (result.getSetField()) {
                    case SUCCESS_RESULT ->
                            disputeCreateResultHandler.handleCheckStatusResult(dispute, result, providerData);
                    case FAIL_RESULT -> disputeCreateResultHandler.handleFailedResult(dispute, result);
                    case ALREADY_EXIST_RESULT -> disputeCreateResultHandler.handleAlreadyExistResult(dispute);
                    case RETRY_LATER -> disputeCreateResultHandler.handleRetryLaterResult(dispute, providerData);
                    default -> throw new IllegalArgumentException(result.getSetField().getFieldName());
                }
            };
            var attachments = attachmentsService.getAttachments(dispute);
            var createDisputeByRemoteClient = (Runnable) () -> finishCreateDisputeResult.accept(
                    remoteClient.createDispute(dispute, attachments, providerData, invoicePayment.getLastTransactionInfo()));
            var createDisputeByDefaultClient = (Runnable) () -> finishCreateDisputeResult.accept(
                    defaultRemoteClient.createDispute(dispute, attachments, providerData, invoicePayment.getLastTransactionInfo()));
            if (providerData.getOptions().containsKey(DISPUTE_FLOW_PROVIDERS_API_EXIST)) {
                createDisputeByRemoteClient(dispute, providerData, createDisputeByRemoteClient, createDisputeByDefaultClient);
            } else {
                log.info("Trying to call defaultRemoteClient.createDispute() by case options!=DISPUTE_FLOW_PROVIDERS_API_EXIST");
                createDisputeByDefaultClient(dispute, createDisputeByDefaultClient);
            }
        } catch (NotFoundException ex) {
            log.error("NotFound when handle CreatedDisputesService.callCreateDisputeRemotely, type={}", ex.getType(), ex);
            switch (ex.getType()) {
                case INVOICE -> disputeCreateResultHandler.handleFailedResult(dispute, ErrorMessage.INVOICE_NOT_FOUND);
                case PAYMENT -> disputeCreateResultHandler.handleFailedResult(dispute, ErrorMessage.PAYMENT_NOT_FOUND);
                case ATTACHMENT, FILEMETA ->
                        disputeCreateResultHandler.handleFailedResult(dispute, ErrorMessage.NO_ATTACHMENTS);
                case DISPUTE -> log.debug("Dispute locked {}", dispute);
                default -> throw ex;
            }
        } catch (CapturedPaymentException ex) {
            log.info("CapturedPaymentException when handle CreatedDisputesService.callCreateDisputeRemotely", ex);
            disputeCreateResultHandler.handleSucceededResult(dispute, getChangedAmount(ex.getInvoicePayment().getPayment()));
        } catch (InvoicingPaymentStatusRestrictionsException ex) {
            log.error("InvoicingPaymentRestrictionStatus when handle CreatedDisputesService.callCreateDisputeRemotely", ex);
            disputeCreateResultHandler.handleFailedResult(dispute, PaymentStatusValidator.getInvoicingPaymentStatusRestrictionsErrorReason(ex));
        } catch (DisputeStatusWasUpdatedByAnotherThreadException ex) {
            log.debug("DisputeStatusWasUpdatedByAnotherThread when handle CreatedDisputesService.callCreateDisputeRemotely", ex);
        }
    }

    private void createDisputeByRemoteClient(Dispute dispute, ProviderData providerData, Runnable createDisputeByRemoteClient, Runnable createDisputeByDefaultClient) {
        woodyRuntimeExceptionCatcher.catchUnexpectedResultMapping(
                () -> woodyRuntimeExceptionCatcher.catchProviderDisputesApiNotExist(
                        providerData,
                        createDisputeByRemoteClient,
                        () -> createDisputeByDefaultClient(dispute, createDisputeByDefaultClient)),
                ex -> disputeCreateResultHandler.handleUnexpectedResultMapping(dispute, ex));
    }

    private void createDisputeByDefaultClient(Dispute dispute, Runnable createDisputeByDefaultClient) {
        woodyRuntimeExceptionCatcher.catchUnexpectedResultMapping(
                createDisputeByDefaultClient,
                ex -> disputeCreateResultHandler.handleUnexpectedResultMapping(dispute, ex));
    }

    private PaymentStatusResult checkProviderPaymentStatus(Dispute dispute, ProviderData providerData, TransactionInfo transactionInfo) {
        var transactionContext = transactionContextConverter.convert(dispute.getInvoiceId(), dispute.getPaymentId(), dispute.getProviderTrxId(), providerData, transactionInfo);
        var currency = disputeCurrencyConverter.convert(dispute);
        return providerPaymentsRemoteClient.checkPaymentStatus(transactionContext, currency, providerData);
    }

    private void handleSucceededResultWithCreateAdjustment(Dispute dispute, PaymentStatusResult providerStatus, ProviderData providerData, TransactionInfo transactionInfo) {
        disputeStatusResultHandler.handleSucceededResult(
                dispute, getDisputeStatusResult(providerStatus.getChangedAmount().orElse(null)), providerData, transactionInfo);
    }

    private DisputeStatusResult getDisputeStatusResult(Long changedAmount) {
        return Optional.ofNullable(changedAmount)
                .map(amount -> DisputeStatusResult.statusSuccess(new DisputeStatusSuccessResult().setChangedAmount(amount)))
                .orElse(DisputeStatusResult.statusSuccess(new DisputeStatusSuccessResult()));
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/core/ForgottenDisputesService.java
MD5:  9b64c3e3cf993b53ec8eab7bef24d91e
SHA1: 42553b9a2f342434b7743cbabae7487eb9d2abc9
package dev.vality.disputes.schedule.core;

import dev.vality.disputes.constant.ErrorMessage;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.exception.CapturedPaymentException;
import dev.vality.disputes.exception.DisputeStatusWasUpdatedByAnotherThreadException;
import dev.vality.disputes.exception.InvoicingPaymentStatusRestrictionsException;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.schedule.service.ProviderDataService;
import dev.vality.disputes.service.DisputesService;
import dev.vality.disputes.service.external.InvoicingService;
import dev.vality.disputes.util.PaymentStatusValidator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

import static dev.vality.disputes.util.PaymentAmountUtil.getChangedAmount;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ForgottenDisputesService {

    private final DisputesService disputesService;
    private final InvoicingService invoicingService;
    private final ProviderDataService providerDataService;

    @Transactional
    public List<Dispute> getForgottenSkipLocked(int batchSize) {
        return disputesService.getForgottenSkipLocked(batchSize);
    }

    @Transactional
    public void process(Dispute dispute) {
        try {
            // validate
            disputesService.checkPendingStatuses(dispute);
            // validate
            var invoicePayment = invoicingService.getInvoicePayment(dispute.getInvoiceId(), dispute.getPaymentId());
            // validate
            PaymentStatusValidator.checkStatus(invoicePayment);
            var providerData = providerDataService.getProviderData(dispute.getProviderId(), dispute.getTerminalId());
            disputesService.updateNextPollingInterval(dispute, providerData);
        } catch (NotFoundException ex) {
            log.error("NotFound when handle ForgottenDisputesService.process, type={}", ex.getType(), ex);
            switch (ex.getType()) {
                case INVOICE -> disputesService.finishFailed(dispute, ErrorMessage.INVOICE_NOT_FOUND);
                case PAYMENT -> disputesService.finishFailed(dispute, ErrorMessage.PAYMENT_NOT_FOUND);
                case DISPUTE -> log.debug("Dispute locked {}", dispute);
                default -> throw ex;
            }
        } catch (CapturedPaymentException ex) {
            log.info("CapturedPaymentException when handle ForgottenDisputesService.process", ex);
            disputesService.finishSucceeded(dispute, getChangedAmount(ex.getInvoicePayment().getPayment()));
        } catch (InvoicingPaymentStatusRestrictionsException ex) {
            log.error("InvoicingPaymentRestrictionStatus when handle ForgottenDisputesService.process", ex);
            disputesService.finishFailed(dispute, PaymentStatusValidator.getInvoicingPaymentStatusRestrictionsErrorReason(ex));
        } catch (DisputeStatusWasUpdatedByAnotherThreadException ex) {
            log.debug("DisputeStatusWasUpdatedByAnotherThread when handle ForgottenDisputesService.process", ex);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/core/NotificationService.java
MD5:  5446837c514fd7926263e1edf2eb2164
SHA1: 49bd79d417d167118868315dedc832fa72515b8b
package dev.vality.disputes.schedule.core;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.vality.disputes.admin.MerchantsNotificationParamsRequest;
import dev.vality.disputes.dao.DisputeDao;
import dev.vality.disputes.dao.NotificationDao;
import dev.vality.disputes.domain.enums.NotificationStatus;
import dev.vality.disputes.domain.tables.pojos.Notification;
import dev.vality.disputes.exception.NotificationStatusWasUpdatedByAnotherThreadException;
import dev.vality.disputes.polling.ExponentialBackOffPollingServiceWrapper;
import dev.vality.disputes.schedule.service.ProviderDataService;
import dev.vality.swag.disputes.model.NotifyRequest;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.apache.hc.client5.http.classic.methods.HttpPost;
import org.apache.hc.client5.http.impl.classic.BasicHttpClientResponseHandler;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.ContentType;
import org.apache.hc.core5.http.io.entity.HttpEntities;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.util.List;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class NotificationService {

    private final DisputeDao disputeDao;
    private final NotificationDao notificationDao;
    private final ProviderDataService providerDataService;
    private final CloseableHttpClient httpClient;
    private final ObjectMapper customObjectMapper;
    private final ExponentialBackOffPollingServiceWrapper exponentialBackOffPollingService;

    @Transactional
    public List<NotifyRequest> getNotifyRequests(int batchSize) {
        return notificationDao.getNotifyRequests(batchSize);
    }

    @Transactional
    @SneakyThrows
    public void process(NotifyRequest notifyRequest) {
        var plainTextBody = customObjectMapper.writeValueAsString(notifyRequest);
        try {
            var forUpdate = checkPending(notifyRequest);
            var httpRequest = new HttpPost(forUpdate.getNotificationUrl());
            httpRequest.setEntity(HttpEntities.create(plainTextBody, ContentType.APPLICATION_JSON));
            httpClient.execute(httpRequest, new BasicHttpClientResponseHandler());
            notificationDao.delivered(forUpdate);
            log.info("Delivered NotifyRequest {}", notifyRequest);
        } catch (IOException ex) {
            log.info("IOException when handle NotificationService.process {}", notifyRequest, ex);
            var forUpdate = checkPending(notifyRequest);
            var dispute = disputeDao.get(UUID.fromString(notifyRequest.getDisputeId()));
            var providerData = providerDataService.getProviderData(dispute.getProviderId(), dispute.getTerminalId());
            var nextAttemptAfter = exponentialBackOffPollingService.prepareNextPollingInterval(forUpdate, dispute.getCreatedAt(), providerData.getOptions());
            notificationDao.updateNextAttempt(forUpdate, nextAttemptAfter);
            log.debug("Finish IOException handler {}", notifyRequest, ex);
        } catch (NotificationStatusWasUpdatedByAnotherThreadException ex) {
            log.debug("NotificationStatusWasUpdatedByAnotherThreadException when handle NotificationService.process", ex);
        }
    }

    @SneakyThrows
    public void sendMerchantsNotification(MerchantsNotificationParamsRequest params) {
        var dispute = disputeDao.getByInvoiceId(params.getInvoiceId(), params.getPaymentId());
        var notifyRequest = notificationDao.getNotifyRequest(dispute.getId());
        var forUpdate = checkPending(notifyRequest);
        var httpRequest = new HttpPost(forUpdate.getNotificationUrl());
        var plainTextBody = customObjectMapper.writeValueAsString(notifyRequest);
        httpRequest.setEntity(HttpEntities.create(plainTextBody, ContentType.APPLICATION_JSON));
        httpClient.execute(httpRequest, new BasicHttpClientResponseHandler());
        log.info("Delivered NotifyRequest by MerchantsNotificationParamsRequest {}", notifyRequest);
    }

    private Notification checkPending(NotifyRequest notifyRequest) {
        var forUpdate = notificationDao.getSkipLocked(UUID.fromString(notifyRequest.getDisputeId()));
        if (forUpdate.getStatus() != NotificationStatus.pending) {
            throw new NotificationStatusWasUpdatedByAnotherThreadException();
        }
        return forUpdate;
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/core/PendingDisputesService.java
MD5:  a9bc35585986998bacfdc6e25bf1ef64
SHA1: b0167e09002630c5ad7fddec70d13eccd2a8cd2b
package dev.vality.disputes.schedule.core;

import dev.vality.disputes.constant.ErrorMessage;
import dev.vality.disputes.dao.ProviderDisputeDao;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.exception.*;
import dev.vality.disputes.polling.PollingInfoService;
import dev.vality.disputes.provider.DisputeStatusResult;
import dev.vality.disputes.schedule.catcher.WoodyRuntimeExceptionCatcher;
import dev.vality.disputes.schedule.client.RemoteClient;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.disputes.schedule.result.DisputeStatusResultHandler;
import dev.vality.disputes.schedule.service.ProviderDataService;
import dev.vality.disputes.service.DisputesService;
import dev.vality.disputes.service.external.InvoicingService;
import dev.vality.disputes.util.PaymentStatusValidator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.function.Consumer;

import static dev.vality.disputes.util.PaymentAmountUtil.getChangedAmount;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class PendingDisputesService {

    private final RemoteClient remoteClient;
    private final DisputesService disputesService;
    private final ProviderDisputeDao providerDisputeDao;
    private final InvoicingService invoicingService;
    private final PollingInfoService pollingInfoService;
    private final ProviderDataService providerDataService;
    private final DisputeStatusResultHandler disputeStatusResultHandler;
    private final WoodyRuntimeExceptionCatcher woodyRuntimeExceptionCatcher;

    @Transactional
    public List<Dispute> getPendingSkipLocked(int batchSize) {
        return disputesService.getPendingSkipLocked(batchSize);
    }

    @Transactional
    public void callPendingDisputeRemotely(Dispute dispute) {
        try {
            // validate
            disputesService.checkPendingStatus(dispute);
            // validate
            pollingInfoService.checkDeadline(dispute);
            // validate
            var invoicePayment = invoicingService.getInvoicePayment(dispute.getInvoiceId(), dispute.getPaymentId());
            // validate
            PaymentStatusValidator.checkStatus(invoicePayment);
            var providerData = getProviderData(dispute);
            var finishCheckDisputeStatusResult = (Consumer<DisputeStatusResult>) result -> {
                switch (result.getSetField()) {
                    case STATUS_SUCCESS -> disputeStatusResultHandler.handleSucceededResult(
                            dispute, result, providerData, invoicePayment.getLastTransactionInfo());
                    case STATUS_FAIL -> disputeStatusResultHandler.handleFailedResult(dispute, result);
                    case STATUS_PENDING -> disputeStatusResultHandler.handlePendingResult(dispute, providerData);
                    default -> throw new IllegalArgumentException(result.getSetField().getFieldName());
                }
            };
            var providerDispute = providerDisputeDao.get(dispute.getId());
            var checkDisputeStatusByRemoteClient = (Runnable) () -> finishCheckDisputeStatusResult.accept(
                    remoteClient.checkDisputeStatus(dispute, providerDispute, providerData, invoicePayment.getLastTransactionInfo()));
            checkDisputeStatusByRemoteClient(dispute, checkDisputeStatusByRemoteClient);
        } catch (NotFoundException ex) {
            log.error("NotFound when handle PendingDisputesService.callPendingDisputeRemotely, type={}", ex.getType(), ex);
            switch (ex.getType()) {
                case INVOICE -> disputeStatusResultHandler.handleFailedResult(dispute, ErrorMessage.INVOICE_NOT_FOUND);
                case PAYMENT -> disputeStatusResultHandler.handleFailedResult(dispute, ErrorMessage.PAYMENT_NOT_FOUND);
                case PROVIDERDISPUTE -> disputeStatusResultHandler.handleProviderDisputeNotFound(
                        dispute, getProviderData(dispute));
                case DISPUTE -> log.debug("Dispute locked {}", dispute);
                default -> throw ex;
            }
        } catch (PoolingExpiredException ex) {
            log.error("PoolingExpired when handle PendingDisputesService.callPendingDisputeRemotely", ex);
            disputeStatusResultHandler.handlePoolingExpired(dispute);
        } catch (CapturedPaymentException ex) {
            log.info("CapturedPaymentException when handle PendingDisputesService.callPendingDisputeRemotely", ex);
            disputeStatusResultHandler.handleSucceededResult(dispute, getChangedAmount(ex.getInvoicePayment().getPayment()));
        } catch (InvoicingPaymentStatusRestrictionsException ex) {
            log.error("InvoicingPaymentRestrictionStatus when handle PendingDisputesService.callPendingDisputeRemotely", ex);
            disputeStatusResultHandler.handleFailedResult(dispute, PaymentStatusValidator.getInvoicingPaymentStatusRestrictionsErrorReason(ex));
        } catch (DisputeStatusWasUpdatedByAnotherThreadException ex) {
            log.debug("DisputeStatusWasUpdatedByAnotherThread when handle CreatedDisputesService.callPendingDisputeRemotely", ex);
        }
    }

    private void checkDisputeStatusByRemoteClient(Dispute dispute, Runnable checkDisputeStatusByRemoteClient) {
        woodyRuntimeExceptionCatcher.catchUnexpectedResultMapping(
                checkDisputeStatusByRemoteClient,
                ex -> disputeStatusResultHandler.handleUnexpectedResultMapping(dispute, ex));
    }

    private ProviderData getProviderData(Dispute dispute) {
        return providerDataService.getProviderData(dispute.getProviderId(), dispute.getTerminalId());
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/handler/CreatedDisputeHandler.java
MD5:  6077e1f91c837b17bd895bc2374d8f99
SHA1: a7561bb2e85ffafabbd7106da1bb0e21bc399a32
package dev.vality.disputes.schedule.handler;

import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.schedule.core.CreatedDisputesService;
import lombok.RequiredArgsConstructor;

import java.util.UUID;

@RequiredArgsConstructor
public class CreatedDisputeHandler {

    private final CreatedDisputesService createdDisputesService;

    public UUID handle(Dispute dispute) {
        final var currentThread = Thread.currentThread();
        final var oldName = currentThread.getName();
        currentThread.setName("dispute-created-id-" + dispute.getId() + "-" + oldName);
        try {
            createdDisputesService.callCreateDisputeRemotely(dispute);
            return dispute.getId();
        } finally {
            currentThread.setName(oldName);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/handler/ForgottenDisputeHandler.java
MD5:  7470a1f80c8c8ab201ab8f2bfe488dd9
SHA1: c3622fd6c32f6bdfbbbbe086a208becd6d0f141a
package dev.vality.disputes.schedule.handler;

import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.schedule.core.ForgottenDisputesService;
import lombok.RequiredArgsConstructor;

import java.util.UUID;

@RequiredArgsConstructor
public class ForgottenDisputeHandler {

    private final ForgottenDisputesService forgottenDisputesService;

    public UUID handle(Dispute dispute) {
        final var currentThread = Thread.currentThread();
        final var oldName = currentThread.getName();
        currentThread.setName("dispute-forgotten-id-" + dispute.getId() + "-" + oldName);
        try {
            forgottenDisputesService.process(dispute);
            return dispute.getId();
        } finally {
            currentThread.setName(oldName);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/handler/NotificationHandler.java
MD5:  84188c2166055d0a07b08b3e502292f6
SHA1: ba834dba7dda6c2ac2199ecb49dfc5e26c7da0f8
package dev.vality.disputes.schedule.handler;

import dev.vality.disputes.schedule.core.NotificationService;
import dev.vality.swag.disputes.model.NotifyRequest;
import lombok.RequiredArgsConstructor;

@RequiredArgsConstructor
public class NotificationHandler {

    private final NotificationService notificationService;

    public String handle(NotifyRequest notifyRequest) {
        final var currentThread = Thread.currentThread();
        final var oldName = currentThread.getName();
        currentThread.setName("notification-id-" + notifyRequest.getDisputeId() + "-" + oldName);
        try {
            notificationService.process(notifyRequest);
            return notifyRequest.getDisputeId();
        } finally {
            currentThread.setName(oldName);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/handler/PendingDisputeHandler.java
MD5:  1a8ea1e92ff5e1bd2dad3c3dbaeaa2ab
SHA1: b76c1aff194896e5a10701ccbfe48bf21d69f6d0
package dev.vality.disputes.schedule.handler;

import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.schedule.core.PendingDisputesService;
import lombok.RequiredArgsConstructor;

import java.util.UUID;

@RequiredArgsConstructor
public class PendingDisputeHandler {

    private final PendingDisputesService pendingDisputesService;

    public UUID handle(Dispute dispute) {
        final var currentThread = Thread.currentThread();
        final var oldName = currentThread.getName();
        currentThread.setName("dispute-pending-id-" + dispute.getId() + "-" + oldName);
        try {
            pendingDisputesService.callPendingDisputeRemotely(dispute);
            return dispute.getId();
        } finally {
            currentThread.setName(oldName);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/model/ProviderData.java
MD5:  275a6f313b21025d204554ae2ba95f52
SHA1: 7d7fb04a9abcf75c097ae834a5a8736cc3bdf927
package dev.vality.disputes.schedule.model;

import lombok.Builder;
import lombok.Data;

import java.util.Map;

@Data
@Builder
public class ProviderData {

    private Map<String, String> options;
    private String defaultProviderUrl;
    private String routeUrl;

}


FILE: ./src/main/java/dev/vality/disputes/schedule/result/DisputeCreateResultHandler.java
MD5:  f8335a76220ff38ddf2d169702143cf2
SHA1: c5a45de88e09aede25775fee5be0a1773a8fc3dd
package dev.vality.disputes.schedule.result;

import dev.vality.disputes.admin.callback.CallbackNotifier;
import dev.vality.disputes.constant.ErrorMessage;
import dev.vality.disputes.dao.ProviderDisputeDao;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.provider.DisputeCreatedResult;
import dev.vality.disputes.schedule.client.DefaultRemoteClient;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.disputes.service.DisputesService;
import dev.vality.disputes.util.ErrorFormatter;
import dev.vality.woody.api.flow.error.WRuntimeException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import static dev.vality.disputes.constant.ModerationPrefix.DISPUTES_UNKNOWN_MAPPING;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class DisputeCreateResultHandler {

    private final DisputesService disputesService;
    private final DefaultRemoteClient defaultRemoteClient;
    private final ProviderDisputeDao providerDisputeDao;
    private final CallbackNotifier callbackNotifier;

    public void handleRetryLaterResult(Dispute dispute, ProviderData providerData) {
        // дергаем update() чтоб обновить время вызова next_check_after,
        // чтобы шедулатор далее доставал пачку самых древних диспутов и смещал
        // и этим вызовом мы финализируем состояние диспута, что он был обновлен недавно
        disputesService.setNextStepToCreated(dispute, providerData);
    }

    public void handleCheckStatusResult(Dispute dispute, DisputeCreatedResult result, ProviderData providerData) {
        providerDisputeDao.save(result.getSuccessResult().getProviderDisputeId(), dispute);
        var isDefaultRouteUrl = defaultRemoteClient.routeUrlEquals(providerData);
        if (isDefaultRouteUrl) {
            disputesService.setNextStepToManualPending(dispute, ErrorMessage.NEXT_STEP_AFTER_DEFAULT_REMOTE_CLIENT_CALL);
        } else {
            disputesService.setNextStepToPending(dispute, providerData);
        }
    }

    public void handleSucceededResult(Dispute dispute, Long changedAmount) {
        disputesService.finishSucceeded(dispute, changedAmount);
    }

    public void handleFailedResult(Dispute dispute, DisputeCreatedResult result) {
        var failure = result.getFailResult().getFailure();
        var errorMessage = ErrorFormatter.getErrorMessage(failure);
        if (errorMessage.startsWith(DISPUTES_UNKNOWN_MAPPING)) {
            handleUnexpectedResultMapping(dispute, failure.getCode(), failure.getReason());
        } else {
            disputesService.finishFailedWithMapping(dispute, errorMessage, failure);
        }
    }

    public void handleFailedResult(Dispute dispute, String errorMessage) {
        disputesService.finishFailed(dispute, errorMessage);
    }

    public void handleAlreadyExistResult(Dispute dispute) {
        disputesService.setNextStepToAlreadyExist(dispute);
        callbackNotifier.sendDisputeAlreadyCreated(dispute);
    }

    public void handleUnexpectedResultMapping(Dispute dispute, WRuntimeException ex) {
        var errorMessage = ex.getErrorDefinition().getErrorReason();
        handleUnexpectedResultMapping(dispute, errorMessage, null);
    }

    private void handleUnexpectedResultMapping(Dispute dispute, String errorCode, String errorDescription) {
        var errorMessage = ErrorFormatter.getErrorMessage(errorCode, errorDescription);
        disputesService.setNextStepToManualPending(dispute, errorMessage);
        callbackNotifier.sendDisputeManualPending(dispute, errorMessage);
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/result/DisputeStatusResultHandler.java
MD5:  f86a1b7b19fad7aa5581ff77ae7231f1
SHA1: f87cb8147b318f4491d7652dc4658fae357056c3
package dev.vality.disputes.schedule.result;

import dev.vality.damsel.domain.TransactionInfo;
import dev.vality.disputes.admin.callback.CallbackNotifier;
import dev.vality.disputes.constant.ErrorMessage;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.provider.DisputeStatusResult;
import dev.vality.disputes.provider.payments.converter.TransactionContextConverter;
import dev.vality.disputes.provider.payments.exception.ProviderCallbackAlreadyExistException;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsService;
import dev.vality.disputes.schedule.converter.DisputeCurrencyConverter;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.disputes.service.DisputesService;
import dev.vality.disputes.util.ErrorFormatter;
import dev.vality.woody.api.flow.error.WRuntimeException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import static dev.vality.disputes.constant.ModerationPrefix.DISPUTES_UNKNOWN_MAPPING;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class DisputeStatusResultHandler {

    private final DisputesService disputesService;
    private final ProviderPaymentsService providerPaymentsService;
    private final TransactionContextConverter transactionContextConverter;
    private final DisputeCurrencyConverter disputeCurrencyConverter;
    private final CallbackNotifier callbackNotifier;

    public void handlePendingResult(Dispute dispute, ProviderData providerData) {
        // дергаем update() чтоб обновить время вызова next_check_after,
        // чтобы шедулатор далее доставал пачку самых древних диспутов и смещал
        // и этим вызовом мы финализируем состояние диспута, что он был обновлен недавно
        disputesService.setNextStepToPending(dispute, providerData);
    }

    public void handleFailedResult(Dispute dispute, DisputeStatusResult result) {
        var failure = result.getStatusFail().getFailure();
        var errorMessage = ErrorFormatter.getErrorMessage(failure);
        if (errorMessage.startsWith(DISPUTES_UNKNOWN_MAPPING)) {
            handleUnexpectedResultMapping(dispute, failure.getCode(), failure.getReason());
        } else {
            disputesService.finishFailedWithMapping(dispute, errorMessage, failure);
        }
    }

    public void handleFailedResult(Dispute dispute, String errorMessage) {
        disputesService.finishFailed(dispute, errorMessage);
    }

    public void handleSucceededResult(Dispute dispute, Long changedAmount) {
        disputesService.finishSucceeded(dispute, changedAmount);
    }

    public void handleSucceededResult(Dispute dispute, DisputeStatusResult result, ProviderData providerData, TransactionInfo transactionInfo) {
        var changedAmount = result.getStatusSuccess().getChangedAmount().orElse(null);
        disputesService.setNextStepToCreateAdjustment(dispute, changedAmount);
        createAdjustment(dispute, providerData, transactionInfo);
    }

    public void handlePoolingExpired(Dispute dispute) {
        disputesService.setNextStepToPoolingExpired(dispute, ErrorMessage.POOLING_EXPIRED);
        callbackNotifier.sendDisputePoolingExpired(dispute);
    }

    public void handleProviderDisputeNotFound(Dispute dispute, ProviderData providerData) {
        // вернуть в CreatedDisputeService и попробовать создать диспут в провайдере заново, должно быть 0% заходов сюда
        disputesService.setNextStepToCreated(dispute, providerData);
    }

    public void handleUnexpectedResultMapping(Dispute dispute, WRuntimeException ex) {
        var errorMessage = ex.getErrorDefinition().getErrorReason();
        handleUnexpectedResultMapping(dispute, errorMessage, null);
    }

    private void handleUnexpectedResultMapping(Dispute dispute, String errorCode, String errorDescription) {
        var errorMessage = ErrorFormatter.getErrorMessage(errorCode, errorDescription);
        disputesService.setNextStepToManualPending(dispute, errorMessage);
        callbackNotifier.sendDisputeManualPending(dispute, errorMessage);
    }

    private void createAdjustment(Dispute dispute, ProviderData providerData, TransactionInfo transactionInfo) {
        var transactionContext = transactionContextConverter.convert(dispute.getInvoiceId(), dispute.getPaymentId(), dispute.getProviderTrxId(), providerData, transactionInfo);
        var currency = disputeCurrencyConverter.convert(dispute);
        try {
            providerPaymentsService.checkPaymentStatusAndSave(transactionContext, currency, providerData, dispute.getAmount());
        } catch (ProviderCallbackAlreadyExistException ex) {
            log.warn("ProviderCallbackAlreadyExist when handle providerPaymentsService.checkPaymentStatusAndSave", ex);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/service/AttachmentsService.java
MD5:  3296c4b0fab2082e9f475c375092440a
SHA1: c6d590e9eaa159793be1f262c91ea92216aa010f
package dev.vality.disputes.schedule.service;

import dev.vality.disputes.dao.FileMetaDao;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.provider.Attachment;
import dev.vality.disputes.service.external.FileStorageService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor
@Slf4j
public class AttachmentsService {

    private final FileMetaDao fileMetaDao;
    private final FileStorageService fileStorageService;

    public List<Attachment> getAttachments(Dispute dispute) {
        log.debug("Trying to get Attachments {}", dispute);
        var attachments = new ArrayList<Attachment>();
        for (var fileMeta : fileMetaDao.getDisputeFiles(dispute.getId())) {
            var attachment = new Attachment();
            attachment.setSourceUrl(fileStorageService.generateDownloadUrl(fileMeta.getFileId()));
            attachment.setMimeType(fileMeta.getMimeType());
            attachments.add(attachment);
        }
        log.debug("Attachments have been found {}", dispute);
        return attachments;
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/service/ExternalGatewayChecker.java
MD5:  bda739198540dd7c56719a682ea4cca1
SHA1: 3dcdfc2cdd17e860c0a63f65a5eee2db465f5033
package dev.vality.disputes.schedule.service;

import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.woody.api.flow.error.WErrorSource;
import dev.vality.woody.api.flow.error.WErrorType;
import dev.vality.woody.api.flow.error.WRuntimeException;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.HttpStatus;
import org.apache.hc.core5.http.io.HttpClientResponseHandler;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ExternalGatewayChecker {

    private final CloseableHttpClient httpClient;
    private final ProviderDisputesRouting providerDisputesRouting;

    public boolean isProviderDisputesUnexpectedResultMapping(WRuntimeException ex) {
        return ex.getErrorDefinition() != null
                && ex.getErrorDefinition().getGenerationSource() == WErrorSource.EXTERNAL
                && ex.getErrorDefinition().getErrorType() == WErrorType.UNEXPECTED_ERROR
                && ex.getErrorDefinition().getErrorSource() == WErrorSource.INTERNAL
                && ex.getErrorDefinition().getErrorReason() != null
                && ex.getErrorDefinition().getErrorReason().contains("code = ")
                && ex.getErrorDefinition().getErrorReason().contains("description = ");
    }

    public boolean isProviderDisputesApiNotExist(ProviderData providerData, WRuntimeException ex) {
        return ex.getErrorDefinition() != null
                && ex.getErrorDefinition().getGenerationSource() == WErrorSource.EXTERNAL
                && ex.getErrorDefinition().getErrorType() == WErrorType.UNEXPECTED_ERROR
                && ex.getErrorDefinition().getErrorSource() == WErrorSource.INTERNAL
                && isProviderDisputesApiNotFound(providerData);
    }

    @SneakyThrows
    private Boolean isProviderDisputesApiNotFound(ProviderData providerData) {
        return httpClient.execute(new HttpGet(getRouteUrl(providerData)), isNotFoundResponse());
    }

    private String getRouteUrl(ProviderData providerData) {
        providerDisputesRouting.initRouteUrl(providerData);
        log.debug("Check adapter connection, routeUrl={}", providerData.getRouteUrl());
        return providerData.getRouteUrl();
    }

    private HttpClientResponseHandler<Boolean> isNotFoundResponse() {
        return response -> {
            log.debug("Check adapter connection, resp={}", response);
            return response.getCode() == HttpStatus.SC_NOT_FOUND;
        };
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/service/ProviderDataService.java
MD5:  852013d8d68d271b0086c725bfe6be53
SHA1: 0cf16bbc31e02646adb78571ff9da470a6b3834d
package dev.vality.disputes.schedule.service;

import dev.vality.damsel.domain.Currency;
import dev.vality.damsel.domain.CurrencyRef;
import dev.vality.damsel.domain.ProviderRef;
import dev.vality.damsel.domain.TerminalRef;
import dev.vality.damsel.payment_processing.InvoicePayment;
import dev.vality.disputes.schedule.model.ProviderData;
import dev.vality.disputes.service.external.DominantService;
import dev.vality.disputes.service.external.impl.dominant.DominantAsyncService;
import dev.vality.disputes.util.OptionsExtractor;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProviderDataService {

    private final DominantService dominantService;
    private final DominantAsyncService dominantAsyncService;

    public ProviderData getProviderData(Integer providerId, Integer terminalId) {
        var provider = dominantService.getProvider(new ProviderRef(providerId));
        var terminal = dominantService.getTerminal(new TerminalRef(terminalId));
        var proxy = dominantService.getProxy(provider.getProxy().getRef());
        return ProviderData.builder()
                .options(OptionsExtractor.mergeOptions(provider, proxy, terminal))
                .defaultProviderUrl(proxy.getUrl())
                .build();
    }

    public ProviderData getProviderData(ProviderRef providerRef, TerminalRef terminalRef) {
        var provider = dominantService.getProvider(providerRef);
        var terminal = dominantService.getTerminal(terminalRef);
        var proxy = dominantService.getProxy(provider.getProxy().getRef());
        return ProviderData.builder()
                .options(OptionsExtractor.mergeOptions(provider, proxy, terminal))
                .defaultProviderUrl(proxy.getUrl())
                .build();
    }

    public Currency getCurrency(CurrencyRef currencyRef) {
        return dominantService.getCurrency(currencyRef);
    }

    @SneakyThrows
    public ProviderData getAsyncProviderData(InvoicePayment payment) {
        var provider = dominantAsyncService.getProvider(payment.getRoute().getProvider());
        var terminal = dominantAsyncService.getTerminal(payment.getRoute().getTerminal());
        var proxy = dominantAsyncService.getProxy(provider.get().getProxy().getRef());
        return ProviderData.builder()
                .options(OptionsExtractor.mergeOptions(provider.get(), proxy.get(), terminal.get()))
                .defaultProviderUrl(proxy.get().getUrl())
                .build();
    }

    @SneakyThrows
    public Currency getAsyncCurrency(InvoicePayment payment) {
        return dominantAsyncService.getCurrency(payment.getPayment().getCost().getCurrency()).get();
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/service/ProviderDisputesRouting.java
MD5:  39b8b64bd8a2f6d6d3f61c1c6422f170
SHA1: 321b0cd9ac64a02f958d4a0bbf7c948b546d2d6f
package dev.vality.disputes.schedule.service;

import dev.vality.disputes.exception.RoutingException;
import dev.vality.disputes.schedule.model.ProviderData;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.util.ObjectUtils;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProviderDisputesRouting {

    private static final String DISPUTES_URL_POSTFIX_DEFAULT = "disputes";
    private static final String OPTION_DISPUTES_URL_FIELD_NAME = "disputes_url";

    public void initRouteUrl(ProviderData providerData) {
        var url = providerData.getOptions().get(OPTION_DISPUTES_URL_FIELD_NAME);
        if (ObjectUtils.isEmpty(url)) {
            url = createDefaultRouteUrl(providerData.getDefaultProviderUrl());
        }
        providerData.setRouteUrl(url);
    }

    private String createDefaultRouteUrl(String defaultProviderUrl) {
        try {
            return UriComponentsBuilder.fromUri(URI.create(defaultProviderUrl))
                    .pathSegment(DISPUTES_URL_POSTFIX_DEFAULT)
                    .encode()
                    .build()
                    .toUriString();
        } catch (Throwable ex) {
            throw new RoutingException("Unable to create default provider url: ", ex);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/schedule/service/ProviderDisputesThriftInterfaceBuilder.java
MD5:  60bd918d080d4931022cde35cbb67c81
SHA1: 33f5d288e82d808b3dfc90a40cda0729522465b7
package dev.vality.disputes.schedule.service;

import dev.vality.disputes.config.properties.AdaptersConnectionProperties;
import dev.vality.disputes.provider.ProviderDisputesServiceSrv;
import dev.vality.woody.thrift.impl.http.THSpawnClientBuilder;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.util.concurrent.TimeUnit;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class ProviderDisputesThriftInterfaceBuilder {

    private final AdaptersConnectionProperties adaptersConnectionProperties;

    @Cacheable(value = "providerDisputes", key = "#root.args[0]", cacheManager = "providerDisputesCacheManager")
    public ProviderDisputesServiceSrv.Iface buildWoodyClient(String routeUrl) {
        log.info("Creating new client for url: {}", routeUrl);
        return new THSpawnClientBuilder()
                .withNetworkTimeout((int) TimeUnit.SECONDS.toMillis(adaptersConnectionProperties.getTimeoutSec()))
                .withAddress(URI.create(routeUrl))
                .build(ProviderDisputesServiceSrv.Iface.class);
    }
}


FILE: ./src/main/java/dev/vality/disputes/security/AccessData.java
MD5:  88743282c871aaf6be264023da9c8bfb
SHA1: 7127c0386518349e7b1414a2ff2957ad3357137c
package dev.vality.disputes.security;

import dev.vality.damsel.payment_processing.Invoice;
import dev.vality.damsel.payment_processing.InvoicePayment;
import dev.vality.token.keeper.AuthData;
import lombok.Builder;
import lombok.Data;
import lombok.Setter;
import lombok.ToString;

@Builder
@Data
@Setter
public class AccessData {

    private Invoice invoice;
    private InvoicePayment payment;
    @ToString.Exclude
    private AuthData authData;

}


FILE: ./src/main/java/dev/vality/disputes/security/AccessService.java
MD5:  f57f9ec4685c7fcaf2713ff4ca1b3f5a
SHA1: 336beea422fbd70274a6ef610e5100ec4e71ed31
package dev.vality.disputes.security;

import dev.vality.damsel.payment_processing.InvoicePayment;
import dev.vality.disputes.exception.AuthorizationException;
import dev.vality.disputes.exception.BouncerException;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.security.service.BouncerService;
import dev.vality.disputes.security.service.TokenKeeperService;
import dev.vality.disputes.service.external.InvoicingService;
import dev.vality.disputes.util.PaymentStatusValidator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import static dev.vality.disputes.exception.NotFoundException.Type;

@Slf4j
@RequiredArgsConstructor
@Service
@SuppressWarnings({"LineLength"})
public class AccessService {

    private final InvoicingService invoicingService;
    private final TokenKeeperService tokenKeeperService;
    private final BouncerService bouncerService;

    @Value("${service.bouncer.auth.enabled}")
    private boolean authEnabled;

    public AccessData approveUserAccess(String invoiceId, String paymentId, boolean checkUserAccessData, boolean checkFailedPaymentStatus) {
        log.debug("Start building AccessData {}{}", invoiceId, paymentId);
        var accessData = buildAccessData(invoiceId, paymentId, checkUserAccessData);
        if (checkFailedPaymentStatus) {
            PaymentStatusValidator.checkStatus(accessData.getPayment());
        }
        if (checkUserAccessData) {
            checkUserAccessData(accessData);
        }
        log.debug("Finish building AccessData {}{}", invoiceId, paymentId);
        return accessData;
    }

    private AccessData buildAccessData(String invoiceId, String paymentId, boolean checkUserAccessData) {
        var authData = checkUserAccessData ? tokenKeeperService.getAuthData() : null;
        var invoice = invoicingService.getInvoice(invoiceId);
        return AccessData.builder()
                .authData(authData)
                .invoice(invoice)
                .payment(getInvoicePayment(invoice, paymentId))
                .build();
    }

    private void checkUserAccessData(AccessData accessData) {
        log.debug("Check the user's rights to perform dispute operation");
        try {
            var resolution = bouncerService.getResolution(accessData);
            switch (resolution.getSetField()) {
                case FORBIDDEN: {
                    if (authEnabled) {
                        throw new AuthorizationException("No rights to perform dispute");
                    } else {
                        log.warn("No rights to perform dispute operation, but auth is disabled");
                    }
                }
                break;
                case RESTRICTED: {
                    if (authEnabled) {
                        var restrictions = resolution.getRestricted().getRestrictions();
                        if (restrictions.isSetCapi()) {
                            restrictions.getCapi().getOp().getShops().stream()
                                    .filter(shop -> shop.getId()
                                            .equals(accessData.getInvoice().getInvoice().getShopId()))
                                    .findFirst()
                                    .orElseThrow(() -> new AuthorizationException("No rights to perform dispute"));
                        }
                    } else {
                        log.warn("Rights to perform dispute are restricted, but auth is disabled");
                    }
                }
                break;
                case ALLOWED:
                    break;
                default:
                    throw new BouncerException(String.format("Resolution %s cannot be processed", resolution));
            }
        } catch (Throwable ex) {
            if (authEnabled) {
                throw ex;
            }
            log.warn("Auth error occurred, but bouncer check is disabled: ", ex);
        }
    }

    private InvoicePayment getInvoicePayment(dev.vality.damsel.payment_processing.Invoice invoice, String paymentId) {
        return invoice.getPayments().stream()
                .filter(p -> paymentId.equals(p.getPayment().getId()) && p.isSetRoute())
                .findFirst()
                .orElseThrow(() -> new NotFoundException(
                        String.format("Payment with id: %s and filled route not found!", paymentId), Type.PAYMENT));
    }
}


FILE: ./src/main/java/dev/vality/disputes/security/BouncerContextFactory.java
MD5:  27df3104a4ed28d503d80983ccb7c58a
SHA1: c410fd3f91f8b37130da2876c4f692775276f274
package dev.vality.disputes.security;

import dev.vality.bouncer.context.v1.ContextFragment;
import dev.vality.bouncer.context.v1.ContextPaymentProcessing;
import dev.vality.bouncer.context.v1.Deployment;
import dev.vality.bouncer.context.v1.Environment;
import dev.vality.bouncer.decisions.Context;
import dev.vality.disputes.config.properties.BouncerProperties;
import dev.vality.disputes.security.converter.ContextFragmentV1ToContextFragmentConverter;
import dev.vality.disputes.security.converter.PaymentProcessingInvoiceToBouncerInvoiceConverter;
import dev.vality.disputes.security.converter.PaymentProcessingInvoiceToCommonApiOperationConverter;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.time.Instant;

@RequiredArgsConstructor
@Component
@Slf4j
public class BouncerContextFactory {

    private final BouncerProperties bouncerProperties;
    private final PaymentProcessingInvoiceToBouncerInvoiceConverter invoiceToPaymentProcConverter;
    private final PaymentProcessingInvoiceToCommonApiOperationConverter invoiceToCapiOpConverter;
    private final ContextFragmentV1ToContextFragmentConverter contextFragmentV1ToContextFragmentConverter;

    @SneakyThrows
    public Context buildContext(AccessData accessData) {
        var contextFragmentV1 = buildCapiContextFragment(accessData);
        var capiContextFragment = contextFragmentV1ToContextFragmentConverter.convertContextFragment(contextFragmentV1);
        var tokenKeeperFragmentContent = accessData.getAuthData().getContext().getContent();
        var tokenKeeperContextFragment =
                contextFragmentV1ToContextFragmentConverter.convertContextFragment(tokenKeeperFragmentContent);
        var context = new Context();
        context.putToFragments(ContextFragmentName.TOKEN_KEEPER, tokenKeeperContextFragment);
        context.putToFragments(ContextFragmentName.CAPI, capiContextFragment);
        return context;
    }

    private ContextFragment buildCapiContextFragment(AccessData accessData) {
        var env = buildEnvironment();
        var contextPaymentProcessing = buildPaymentProcessingContext(accessData);
        var fragment = new ContextFragment();
        return fragment
                .setCapi(invoiceToCapiOpConverter.convert(accessData.getInvoice()))
                .setEnv(env)
                .setPaymentProcessing(contextPaymentProcessing);
    }

    private Environment buildEnvironment() {
        var deployment = new Deployment()
                .setId(bouncerProperties.getDeploymentId());
        return new Environment()
                .setDeployment(deployment)
                .setNow(Instant.now().toString());
    }

    private ContextPaymentProcessing buildPaymentProcessingContext(AccessData accessData) {
        return new ContextPaymentProcessing()
                .setInvoice(invoiceToPaymentProcConverter.convert(accessData.getInvoice()));
    }
}


FILE: ./src/main/java/dev/vality/disputes/security/ContextFragmentName.java
MD5:  85c3a90bc91bfea1b9e4f50d8ccaefe8
SHA1: c6d3d9c7d41eb1ced4482bd883f4983e9650684d
package dev.vality.disputes.security;

import lombok.experimental.UtilityClass;

@UtilityClass
public class ContextFragmentName {

    public static final String CAPI = "capi";
    public static final String TOKEN_KEEPER = "token-keeper";

}


FILE: ./src/main/java/dev/vality/disputes/security/converter/ContextFragmentV1ToContextFragmentConverter.java
MD5:  f72aa1250e3d4ab151f6e1c0bcc64bec
SHA1: cfc2be2e2589515d3309e976d4c602e22ee7cfa3
package dev.vality.disputes.security.converter;

import dev.vality.bouncer.ctx.ContextFragment;
import dev.vality.bouncer.ctx.ContextFragmentType;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.apache.thrift.TException;
import org.apache.thrift.TSerializer;
import org.apache.thrift.transport.TTransportException;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class ContextFragmentV1ToContextFragmentConverter {

    private final TSerializer thriftSerializer = new TSerializer();

    public ContextFragmentV1ToContextFragmentConverter() throws TTransportException {
    }

    @SneakyThrows
    public ContextFragment convertContextFragment(dev.vality.bouncer.context.v1.ContextFragment v1Context) {
        try {
            return convertContextFragment(thriftSerializer.serialize(v1Context));
        } catch (TException ex) {
            log.error("Error during ContextFragmentV1 serialization: ", ex);
            throw ex;
        }
    }

    public ContextFragment convertContextFragment(byte[] v1ContextContent) {
        return new ContextFragment()
                .setType(ContextFragmentType.v1_thrift_binary)
                .setContent(v1ContextContent);
    }
}


FILE: ./src/main/java/dev/vality/disputes/security/converter/PaymentProcessingInvoiceToBouncerInvoiceConverter.java
MD5:  fb797e69d6ed4caffe7a40e2f025d7cb
SHA1: e0944c5ce31ddd1b7174da1af6d7e82c55afaf79
package dev.vality.disputes.security.converter;

import dev.vality.bouncer.base.Entity;
import dev.vality.bouncer.context.v1.Payment;
import dev.vality.damsel.payment_processing.Invoice;
import dev.vality.damsel.payment_processing.InvoicePayment;
import dev.vality.damsel.payment_processing.InvoicePaymentRefund;
import org.springframework.core.convert.converter.Converter;
import org.springframework.stereotype.Component;

import java.util.stream.Collectors;

@Component
public class PaymentProcessingInvoiceToBouncerInvoiceConverter
implements Converter<Invoice, dev.vality.bouncer.context.v1.Invoice> {

    @Override
    public dev.vality.bouncer.context.v1.Invoice convert(Invoice source) {
        var invoice = source.getInvoice();
        return new dev.vality.bouncer.context.v1.Invoice()
                .setId(source.getInvoice().getId())
                .setParty(new Entity().setId(invoice.getOwnerId()))
                .setShop(new Entity().setId(invoice.getShopId()))
                .setPayments(source.isSetPayments()
                        ? source.getPayments().stream().map(this::convertPayment).collect(Collectors.toSet())
                        : null);
    }

    private Payment convertPayment(InvoicePayment invoicePayment) {
        return new Payment().setId(invoicePayment.getPayment().getId())
                .setRefunds(invoicePayment.isSetRefunds()
                        ? invoicePayment.getRefunds().stream().map(this::convertRefund).collect(Collectors.toSet())
                        : null);
    }

    private Entity convertRefund(InvoicePaymentRefund invoiceRefund) {
        return new Entity().setId(invoiceRefund.getRefund().getId());
    }
}


FILE: ./src/main/java/dev/vality/disputes/security/converter/PaymentProcessingInvoiceToCommonApiOperationConverter.java
MD5:  e649d30c6de8b7833b26db65ba154639
SHA1: 7fbe20650fd213bb5d33a445d36e5f604f132d9a
package dev.vality.disputes.security.converter;

import dev.vality.bouncer.base.Entity;
import dev.vality.bouncer.context.v1.CommonAPIOperation;
import dev.vality.damsel.payment_processing.Invoice;
import dev.vality.disputes.config.properties.BouncerProperties;
import lombok.RequiredArgsConstructor;
import org.springframework.core.convert.converter.Converter;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class PaymentProcessingInvoiceToCommonApiOperationConverter
implements Converter<Invoice, dev.vality.bouncer.context.v1.ContextCommonAPI> {

    private final BouncerProperties bouncerProperties;

    @Override
    public dev.vality.bouncer.context.v1.ContextCommonAPI convert(Invoice source) {
        var invoice = source.getInvoice();
        return new dev.vality.bouncer.context.v1.ContextCommonAPI()
                .setOp(new CommonAPIOperation()
                        .setId(bouncerProperties.getOperationId())
                        .setInvoice(new Entity().setId(source.getInvoice().getId()))
                        .setParty(new Entity().setId(invoice.getOwnerId()))
                        .setShop(new Entity().setId(invoice.getShopId())));
    }
}


FILE: ./src/main/java/dev/vality/disputes/security/service/BouncerService.java
MD5:  3c0b98e9eeb64c0b0829487e1432b458
SHA1: d47f542d9b17979ca9fbfcc5501e974148f01beb
package dev.vality.disputes.security.service;

import dev.vality.bouncer.decisions.Resolution;
import dev.vality.disputes.security.AccessData;

public interface BouncerService {

    Resolution getResolution(AccessData accessData);

}


FILE: ./src/main/java/dev/vality/disputes/security/service/TokenKeeperService.java
MD5:  3f3f1e7078bd92c3ab86aa5cc114a74f
SHA1: 96e327975c1d26ebd5a40f205f5fb2dabca27f78
package dev.vality.disputes.security.service;

import dev.vality.token.keeper.AuthData;

public interface TokenKeeperService {

    AuthData getAuthData();

}


FILE: ./src/main/java/dev/vality/disputes/security/service/impl/BouncerServiceImpl.java
MD5:  86e091311adfdbd8ba68d04acfa7c140
SHA1: 9f3e509bbc64f48c7942678e35d5b185c9f1673d
package dev.vality.disputes.security.service.impl;

import dev.vality.bouncer.decisions.ArbiterSrv;
import dev.vality.bouncer.decisions.Resolution;
import dev.vality.disputes.config.properties.BouncerProperties;
import dev.vality.disputes.exception.BouncerException;
import dev.vality.disputes.security.AccessData;
import dev.vality.disputes.security.BouncerContextFactory;
import dev.vality.disputes.security.service.BouncerService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.thrift.TException;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class BouncerServiceImpl implements BouncerService {

    private final BouncerProperties bouncerProperties;
    private final BouncerContextFactory bouncerContextFactory;
    private final ArbiterSrv.Iface bouncerClient;

    @Override
    public Resolution getResolution(AccessData accessData) {
        log.debug("Check access with bouncer context: {}{}", accessData.getInvoice().getInvoice().getId(), accessData.getPayment().getPayment().getId());
        var context = bouncerContextFactory.buildContext(accessData);
        log.debug("Built thrift context: {}{}", accessData.getInvoice().getInvoice().getId(), accessData.getPayment().getPayment().getId());
        try {
            var judge = bouncerClient.judge(bouncerProperties.getRuleSetId(), context);
            log.debug("Have judge: {}", judge);
            var resolution = judge.getResolution();
            log.debug("Resolution: {}", resolution);
            return resolution;
        } catch (TException ex) {
            throw new BouncerException("Error while call bouncer", ex);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/security/service/impl/TokenKeeperServiceImpl.java
MD5:  b3094fd61baa7f6b31211e9b4e0677d0
SHA1: 5d44a51f9aabb2c9906e5c3d040ad5c5b8512c22
package dev.vality.disputes.security.service.impl;

import dev.vality.disputes.exception.TokenKeeperException;
import dev.vality.disputes.security.service.TokenKeeperService;
import dev.vality.token.keeper.AuthData;
import dev.vality.token.keeper.TokenAuthenticatorSrv;
import dev.vality.token.keeper.TokenSourceContext;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.hc.core5.http.HttpHeaders;
import org.apache.thrift.TException;
import org.springframework.stereotype.Service;
import org.springframework.util.ObjectUtils;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.util.Optional;

@Slf4j
@Service
@RequiredArgsConstructor
public class TokenKeeperServiceImpl implements TokenKeeperService {

    private static final String bearerPrefix = "Bearer ";
    private final TokenAuthenticatorSrv.Iface tokenKeeperClient;

    @Override
    public AuthData getAuthData() {
        log.debug("Retrieving auth info");
        try {
            var token = getBearerToken();
            return tokenKeeperClient.authenticate(
                    token.orElseThrow(() -> new TokenKeeperException("Token not found!")), new TokenSourceContext());
        } catch (TException ex) {
            throw new TokenKeeperException("Error while call token keeper: ", ex);
        }
    }

    private Optional<String> getBearerToken() {
        var attributes = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
        if (ObjectUtils.isEmpty(attributes)
                || ObjectUtils.isEmpty(attributes.getRequest().getHeader(HttpHeaders.AUTHORIZATION))) {
            return Optional.empty();
        }
        var token = attributes.getRequest().getHeader(HttpHeaders.AUTHORIZATION).substring(bearerPrefix.length());
        return Optional.of(token);
    }
}


FILE: ./src/main/java/dev/vality/disputes/service/DisputesService.java
MD5:  bf764a1980d7f4df34cdc1514420a662
SHA1: c0f7489cdba6730d72b44cb89ebdb8376dae7fd5
package dev.vality.disputes.service;

import dev.vality.damsel.domain.Failure;
import dev.vality.disputes.dao.DisputeDao;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.exception.DisputeStatusWasUpdatedByAnotherThreadException;
import dev.vality.disputes.polling.ExponentialBackOffPollingServiceWrapper;
import dev.vality.disputes.schedule.model.ProviderData;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class DisputesService {

    public static final Set<DisputeStatus> DISPUTE_PENDING_STATUSES = disputePendingStatuses();
    private final DisputeDao disputeDao;
    private final ExponentialBackOffPollingServiceWrapper exponentialBackOffPollingService;

    public void finishSucceeded(String invoiceId, String paymentId, Long changedAmount) {
        var dispute = Optional.of(disputeDao.getSkipLockedByInvoiceId(invoiceId, paymentId))
                .filter(d -> DISPUTE_PENDING_STATUSES.contains(d.getStatus()))
                .orElseThrow();
        finishSucceeded(dispute, changedAmount);
    }

    public void finishSucceeded(Dispute dispute, Long changedAmount) {
        log.info("Trying to set succeeded Dispute status {}", dispute);
        disputeDao.finishSucceeded(dispute.getId(), changedAmount);
        log.debug("Dispute status has been set to succeeded {}", dispute);
    }

    public void finishFailed(String invoiceId, String paymentId, String errorMessage) {
        var dispute = Optional.of(disputeDao.getSkipLockedByInvoiceId(invoiceId, paymentId))
                .filter(d -> DISPUTE_PENDING_STATUSES.contains(d.getStatus()))
                .orElseThrow();
        finishFailed(dispute, errorMessage);
    }

    public void finishFailed(Dispute dispute, String errorMessage) {
        log.warn("Trying to set failed Dispute status with '{}' errorMessage, {}", errorMessage, dispute.getId());
        disputeDao.finishFailed(dispute.getId(), errorMessage);
        log.debug("Dispute status has been set to failed {}", dispute.getId());
    }

    public void finishFailedWithMapping(Dispute dispute, String errorMessage, Failure failure) {
        log.warn("Trying to set failed Dispute status with '{}' errorMessage, '{}' mapping, {}", errorMessage, failure.getCode(), dispute.getId());
        disputeDao.finishFailedWithMapping(dispute.getId(), errorMessage, failure.getCode());
        log.debug("Dispute status has been set to failed, '{}' mapping, {}", failure.getCode(), dispute.getId());
    }

    public void finishCancelled(Dispute dispute, String mapping, String errorMessage) {
        log.warn("Trying to set cancelled Dispute status with '{}' errorMessage, '{}' mapping, {}", errorMessage, mapping, dispute.getId());
        disputeDao.finishCancelled(dispute.getId(), errorMessage, mapping);
        log.debug("Dispute status has been set to cancelled {}", dispute);
    }

    public void setNextStepToCreated(Dispute dispute, ProviderData providerData) {
        var nextCheckAfter = exponentialBackOffPollingService.prepareNextPollingInterval(dispute, providerData.getOptions());
        log.info("Trying to set created Dispute status {}", dispute.getId());
        disputeDao.setNextStepToCreated(dispute.getId(), nextCheckAfter);
        log.debug("Dispute status has been set to created {}", dispute.getId());
    }

    public void setNextStepToPending(Dispute dispute, ProviderData providerData) {
        var nextCheckAfter = exponentialBackOffPollingService.prepareNextPollingInterval(dispute, providerData.getOptions());
        log.info("Trying to set pending Dispute status {}", dispute);
        disputeDao.setNextStepToPending(dispute.getId(), nextCheckAfter);
        log.debug("Dispute status has been set to pending {}", dispute.getId());
    }

    public void setNextStepToCreateAdjustment(Dispute dispute, Long changedAmount) {
        log.info("Trying to set create_adjustment Dispute status {}", dispute);
        disputeDao.setNextStepToCreateAdjustment(dispute.getId(), changedAmount);
        log.debug("Dispute status has been set to create_adjustment {}", dispute.getId());
    }

    public void setNextStepToManualPending(Dispute dispute, String errorMessage) {
        log.warn("Trying to set manual_pending Dispute status with '{}' errorMessage, {}", errorMessage, dispute.getId());
        disputeDao.setNextStepToManualPending(dispute.getId(), errorMessage);
        log.debug("Dispute status has been set to manual_pending {}", dispute.getId());
    }

    public void setNextStepToAlreadyExist(Dispute dispute) {
        log.info("Trying to set already_exist_created Dispute status {}", dispute);
        disputeDao.setNextStepToAlreadyExist(dispute.getId());
        log.debug("Dispute status has been set to already_exist_created {}", dispute);
    }

    public void setNextStepToPoolingExpired(Dispute dispute, String errorMessage) {
        log.warn("Trying to set pooling_expired Dispute status with '{}' errorMessage, {}", errorMessage, dispute.getId());
        disputeDao.setNextStepToPoolingExpired(dispute.getId(), errorMessage);
        log.debug("Dispute status has been set to pooling_expired {}", dispute.getId());
    }

    public void updateNextPollingInterval(Dispute dispute, ProviderData providerData) {
        var nextCheckAfter = exponentialBackOffPollingService.prepareNextPollingInterval(dispute, providerData.getOptions());
        disputeDao.updateNextPollingInterval(dispute, nextCheckAfter);
    }

    public List<Dispute> getForgottenSkipLocked(int batchSize) {
        var locked = disputeDao.getForgottenSkipLocked(batchSize);
        if (!locked.isEmpty()) {
            log.debug("ForgottenSkipLocked has been found, size={}", locked.size());
        }
        return locked;
    }

    public List<Dispute> getCreatedSkipLocked(int batchSize) {
        var locked = disputeDao.getSkipLocked(batchSize, DisputeStatus.created);
        if (!locked.isEmpty()) {
            log.debug("CreatedSkipLocked has been found, size={}", locked.size());
        }
        return locked;
    }

    public List<Dispute> getPendingSkipLocked(int batchSize) {
        var locked = disputeDao.getSkipLocked(batchSize, DisputeStatus.pending);
        if (!locked.isEmpty()) {
            log.debug("PendingSkipLocked has been found, size={}", locked.size());
        }
        return locked;
    }

    public Dispute getSkipLocked(String disputeId) {
        return disputeDao.getSkipLocked(UUID.fromString(disputeId));
    }

    public Dispute getByInvoiceId(String invoiceId, String paymentId) {
        return disputeDao.getByInvoiceId(invoiceId, paymentId);
    }

    public Dispute getSkipLockedByInvoiceId(String invoiceId, String paymentId) {
        return disputeDao.getSkipLockedByInvoiceId(invoiceId, paymentId);
    }

    public void checkCreatedStatus(Dispute dispute) {
        var forUpdate = getSkipLocked(dispute.getId().toString());
        if (forUpdate.getStatus() != DisputeStatus.created) {
            throw new DisputeStatusWasUpdatedByAnotherThreadException();
        }
    }

    public void checkPendingStatus(Dispute dispute) {
        var forUpdate = getSkipLocked(dispute.getId().toString());
        if (forUpdate.getStatus() != DisputeStatus.pending) {
            throw new DisputeStatusWasUpdatedByAnotherThreadException();
        }
    }

    public void checkPendingStatuses(Dispute dispute) {
        var forUpdate = getSkipLocked(dispute.getId().toString());
        if (!DISPUTE_PENDING_STATUSES.contains(forUpdate.getStatus())) {
            throw new DisputeStatusWasUpdatedByAnotherThreadException();
        }
    }

    private static Set<DisputeStatus> disputePendingStatuses() {
        return Set.of(
                DisputeStatus.created,
                DisputeStatus.pending,
                DisputeStatus.manual_pending,
                DisputeStatus.create_adjustment,
                DisputeStatus.already_exist_created,
                DisputeStatus.pooling_expired);
    }
}


FILE: ./src/main/java/dev/vality/disputes/service/MdcTaskDecorator.java
MD5:  e394aae29694cab7fa22e23b1fa4c2cd
SHA1: a86c5509668a4bac18809a324a408352acefd3c3
package dev.vality.disputes.service;

import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.core.task.TaskDecorator;

@Slf4j
public class MdcTaskDecorator implements TaskDecorator {

    @Override
    public Runnable decorate(Runnable runnable) {
        var contextMap = MDC.getCopyOfContextMap();
        return () -> {
            try {
                if (contextMap != null) {
                    MDC.setContextMap(contextMap);
                }
                runnable.run();
            } finally {
                MDC.clear();
            }
        };
    }
}


FILE: ./src/main/java/dev/vality/disputes/service/external/DisputesTgBotService.java
MD5:  83e28b1b6502d87e776a20ed84f331aa
SHA1: a2f325df6ff98257c4f82b8f4eaf43c7becffc9b
package dev.vality.disputes.service.external;

import dev.vality.disputes.admin.DisputeAlreadyCreated;
import dev.vality.disputes.admin.DisputeManualPending;
import dev.vality.disputes.admin.DisputePoolingExpired;
import dev.vality.disputes.provider.DisputeCreatedResult;
import dev.vality.disputes.provider.DisputeParams;

public interface DisputesTgBotService {

    DisputeCreatedResult createDispute(DisputeParams disputeParams);

    void sendDisputeAlreadyCreated(DisputeAlreadyCreated disputeAlreadyCreated);

    void sendDisputePoolingExpired(DisputePoolingExpired disputePoolingExpired);

    void sendDisputeManualPending(DisputeManualPending disputeManualPending);

}


FILE: ./src/main/java/dev/vality/disputes/service/external/DominantService.java
MD5:  179d5def74406500dfbcb50490bf6efa
SHA1: d589751532c848e2b192b6d8682dbb3ea6eaf685
package dev.vality.disputes.service.external;

import dev.vality.damsel.domain.*;

public interface DominantService {

    Currency getCurrency(CurrencyRef currencyRef);

    Terminal getTerminal(TerminalRef terminalRef);

    ProxyDefinition getProxy(ProxyRef proxyRef);

    Provider getProvider(ProviderRef providerRef);

}


FILE: ./src/main/java/dev/vality/disputes/service/external/FileStorageService.java
MD5:  28e6d4f105f77ea33162d6ffb530feb7
SHA1: abe1623c59345b4147174b3597e664492c503630
package dev.vality.disputes.service.external;

public interface FileStorageService {

    String saveFile(byte[] data);

    String generateDownloadUrl(String fileId);

}


FILE: ./src/main/java/dev/vality/disputes/service/external/InvoicingService.java
MD5:  b369c2ec263ef0412acda2af596e8f28
SHA1: bba684f8f3bab79fdbf3e6c1b5f40aa0b97f48c3
package dev.vality.disputes.service.external;

import dev.vality.damsel.payment_processing.Invoice;
import dev.vality.damsel.payment_processing.InvoicePayment;
import dev.vality.damsel.payment_processing.InvoicePaymentAdjustmentParams;

public interface InvoicingService {

    Invoice getInvoice(String invoiceId);

    InvoicePayment getInvoicePayment(String invoiceId, String paymentId);

    void createPaymentAdjustment(
            String invoiceId,
            String paymentId,
            InvoicePaymentAdjustmentParams params);

}


FILE: ./src/main/java/dev/vality/disputes/service/external/PartyManagementService.java
MD5:  e24e5ab1f79ce9dc8068cfd2461854b7
SHA1: f4ab2a9cdf59559a3dca66fad83dc9a16dd9a38b
package dev.vality.disputes.service.external;

import dev.vality.damsel.domain.Shop;

public interface PartyManagementService {

    Shop getShop(String partyId, String shopId);

}


FILE: ./src/main/java/dev/vality/disputes/service/external/impl/DisputesTgBotServiceImpl.java
MD5:  aa4725953767b17e3123f2c232e2810b
SHA1: 712dcd7ba4f9115d02c2581afc4772c047edddbb
package dev.vality.disputes.service.external.impl;

import dev.vality.disputes.admin.*;
import dev.vality.disputes.provider.DisputeCreatedResult;
import dev.vality.disputes.provider.DisputeParams;
import dev.vality.disputes.provider.ProviderDisputesServiceSrv;
import dev.vality.disputes.service.external.DisputesTgBotService;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
@Slf4j
@SuppressWarnings({"LineLength"})
public class DisputesTgBotServiceImpl implements DisputesTgBotService {

    public final ProviderDisputesServiceSrv.Iface providerDisputesTgBotClient;
    public final AdminCallbackServiceSrv.Iface adminCallbackDisputesTgBotClient;

    @Override
    @SneakyThrows
    public DisputeCreatedResult createDispute(DisputeParams disputeParams) {
        log.debug("Trying to call providerDisputesTgBotClient.createDispute() {} {}", disputeParams.getDisputeId(), disputeParams.getTransactionContext().getInvoiceId());
        var invoice = providerDisputesTgBotClient.createDispute(disputeParams);
        log.debug("providerDisputesTgBotClient.createDispute() has been called {} {}", disputeParams.getDisputeId(), disputeParams.getTransactionContext().getInvoiceId());
        return invoice;
    }

    @Override
    @SneakyThrows
    public void sendDisputeAlreadyCreated(DisputeAlreadyCreated disputeAlreadyCreated) {
        log.debug("Trying to call adminCallbackDisputesTgBotClient.sendDisputeAlreadyCreated() {}", disputeAlreadyCreated.getInvoiceId());
        adminCallbackDisputesTgBotClient.notify(
                new NotificationParamsRequest(List.of(Notification.disputeAlreadyCreated(disputeAlreadyCreated))));
        log.debug("adminCallbackDisputesTgBotClient.sendDisputeAlreadyCreated() has been called {}", disputeAlreadyCreated.getInvoiceId());
    }

    @Override
    @SneakyThrows
    public void sendDisputePoolingExpired(DisputePoolingExpired disputePoolingExpired) {
        log.debug("Trying to call adminCallbackDisputesTgBotClient.sendDisputePoolingExpired() {}", disputePoolingExpired.getInvoiceId());
        adminCallbackDisputesTgBotClient.notify(
                new NotificationParamsRequest(List.of(Notification.disputePoolingExpired(disputePoolingExpired))));
        log.debug("adminCallbackDisputesTgBotClient.sendDisputePoolingExpired() has been called {}", disputePoolingExpired.getInvoiceId());
    }

    @Override
    @SneakyThrows
    public void sendDisputeManualPending(DisputeManualPending disputeManualPending) {
        log.debug("Trying to call adminCallbackDisputesTgBotClient.sendDisputeManualPending() {}", disputeManualPending.getInvoiceId());
        adminCallbackDisputesTgBotClient.notify(
                new NotificationParamsRequest(List.of(Notification.disputeManualPending(disputeManualPending))));
        log.debug("adminCallbackDisputesTgBotClient.sendDisputeManualPending() has been called {}", disputeManualPending.getInvoiceId());
    }
}


FILE: ./src/main/java/dev/vality/disputes/service/external/impl/DominantServiceImpl.java
MD5:  62b58d00fb4863cdeb18341f5cd5e2d9
SHA1: 42177d82e1b1162321ea0e266ceac313280826c0
package dev.vality.disputes.service.external.impl;

import dev.vality.damsel.domain.*;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.service.external.DominantService;
import dev.vality.disputes.service.external.impl.dominant.DominantCacheServiceImpl;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class DominantServiceImpl implements DominantService {

    private final DominantCacheServiceImpl dominantCacheService;

    @Override
    public Currency getCurrency(CurrencyRef currencyRef) throws NotFoundException {
        return dominantCacheService.getCurrency(currencyRef);
    }

    @Override
    public Terminal getTerminal(TerminalRef terminalRef) {
        return dominantCacheService.getTerminal(terminalRef);
    }

    @Override
    public ProxyDefinition getProxy(ProxyRef proxyRef) {
        return dominantCacheService.getProxy(proxyRef);
    }

    @Override
    public Provider getProvider(ProviderRef providerRef) {
        return dominantCacheService.getProvider(providerRef);
    }
}


FILE: ./src/main/java/dev/vality/disputes/service/external/impl/FileStorageServiceImpl.java
MD5:  d0b5777093b580d8e6908bac77186f30
SHA1: a83b4b3621c013b8cfbf58fae918796f3f0add77
package dev.vality.disputes.service.external.impl;

import dev.vality.disputes.config.properties.FileStorageProperties;
import dev.vality.disputes.exception.FileStorageException;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.service.external.FileStorageService;
import dev.vality.file.storage.FileNotFound;
import dev.vality.file.storage.FileStorageSrv;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.apache.hc.client5.http.classic.methods.HttpPut;
import org.apache.hc.client5.http.impl.classic.BasicHttpClientResponseHandler;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.HttpEntities;
import org.apache.thrift.TException;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Collections;

import static dev.vality.disputes.exception.NotFoundException.Type;

@Service
@RequiredArgsConstructor
@Slf4j
@SuppressWarnings({"LineLength"})
public class FileStorageServiceImpl implements FileStorageService {

    private final FileStorageProperties fileStorageProperties;
    private final FileStorageSrv.Iface fileStorageClient;
    private final CloseableHttpClient httpClient;

    @Override
    @SneakyThrows
    public String saveFile(byte[] data) {
        log.debug("Trying to create new file to file-storage");
        var result = fileStorageClient.createNewFile(Collections.emptyMap(), getTime().toString());
        var fileDataId = result.getFileDataId();
        log.debug("Trying to upload data to s3 with id: {}", fileDataId);
        var requestPut = new HttpPut(result.getUploadUrl());
        requestPut.setEntity(HttpEntities.create(data, null));
        // execute() делает внутри try-with-resources + закрывает InputStream в EntityUtils.consume(entity)
        httpClient.execute(requestPut, new BasicHttpClientResponseHandler());
        log.debug("File has been successfully uploaded with id: {}", fileDataId);
        return fileDataId;
    }

    @Override
    public String generateDownloadUrl(String fileId) {
        try {
            log.debug("Trying to generate presigned url from file-storage with id: {}", fileId);
            var url = fileStorageClient.generateDownloadUrl(fileId, getTime().toString());
            if (StringUtils.isBlank(url)) {
                throw new NotFoundException(String.format("Presigned s3 url not found, fileId='%s'", fileId), Type.ATTACHMENT);
            }
            log.debug("Presigned url has been generated with id: {}", fileId);
            return url;
        } catch (FileNotFound ex) {
            throw new NotFoundException(String.format("File not found, fileId='%s'", fileId), ex, Type.ATTACHMENT);
        } catch (TException ex) {
            throw new FileStorageException(String.format("Failed to generateDownloadUrl, fileId='%s'", fileId), ex);
        }
    }

    private Instant getTime() {
        return LocalDateTime.now(fileStorageProperties.getTimeZone())
                .plusMinutes(fileStorageProperties.getUrlLifeTimeDuration())
                .toInstant(ZoneOffset.UTC);
    }
}


FILE: ./src/main/java/dev/vality/disputes/service/external/impl/InvoicingServiceImpl.java
MD5:  a1a67ea38cbe29aae1cb44a0c92ff553
SHA1: 959939598575596b1a26e4f363cee357833e8d4c
package dev.vality.disputes.service.external.impl;

import dev.vality.damsel.payment_processing.*;
import dev.vality.disputes.exception.InvoicePaymentAdjustmentPendingException;
import dev.vality.disputes.exception.InvoicingException;
import dev.vality.disputes.exception.InvoicingPaymentStatusRestrictionsException;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.exception.NotFoundException.Type;
import dev.vality.disputes.service.external.InvoicingService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.thrift.TException;
import org.springframework.stereotype.Service;

import java.util.Optional;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class InvoicingServiceImpl implements InvoicingService {

    private final InvoicingSrv.Iface invoicingClient;

    @Override
    public Invoice getInvoice(String invoiceId) {
        try {
            log.debug("Looking for invoice with id: {}", invoiceId);
            var invoice = Optional.ofNullable(invoicingClient.get(invoiceId, new EventRange()))
                    .orElseThrow(() -> new NotFoundException(String.format("Unable to find invoice with id: %s", invoiceId), Type.INVOICE));
            log.debug("Found invoice with id: {}", invoiceId);
            return invoice;
        } catch (InvoiceNotFound ex) {
            throw new NotFoundException(String.format("Unable to find invoice with id: %s", invoiceId), ex, Type.INVOICE);
        } catch (TException ex) {
            throw new InvoicingException(String.format("Failed to get invoice with id: %s", invoiceId), ex);
        }
    }

    @Override
    public InvoicePayment getInvoicePayment(String invoiceId, String paymentId) {
        try {
            log.debug("Looking for invoicePayment with id: {}", invoiceId);
            var invoicePayment = Optional.ofNullable(invoicingClient.getPayment(invoiceId, paymentId))
                    .orElseThrow(() -> new NotFoundException(String.format("Unable to find invoice with id: %s, paymentId: %s", invoiceId, paymentId), Type.PAYMENT));
            log.debug("Found invoicePayment with id: {}", invoiceId);
            return invoicePayment;
        } catch (InvoiceNotFound ex) {
            throw new NotFoundException(String.format("Unable to find invoice with id: %s", invoiceId), ex, Type.INVOICE);
        } catch (InvoicePaymentNotFound ex) {
            throw new NotFoundException(String.format("Unable to find invoice with id: %s, paymentId: %s", invoiceId, paymentId), ex, Type.PAYMENT);
        } catch (TException ex) {
            throw new InvoicingException(String.format("Failed to get invoicePayment with id: %s, paymentId: %s", invoiceId, paymentId), ex);
        }
    }

    @Override
    public void createPaymentAdjustment(
            String invoiceId,
            String paymentId,
            InvoicePaymentAdjustmentParams params) {
        try {
            log.debug("createPaymentAdjustment with id: {}", invoiceId);
            invoicingClient.createPaymentAdjustment(invoiceId, paymentId, params);
            log.debug("Done createPaymentAdjustment with id: {}", invoiceId);
        } catch (InvoiceNotFound ex) {
            throw new NotFoundException(String.format("Unable to find invoice with id: %s", invoiceId), ex, Type.INVOICE);
        } catch (InvoicePaymentNotFound ex) {
            throw new NotFoundException(String.format("Unable to find invoice with id: %s, paymentId: %s", invoiceId, paymentId), ex, Type.PAYMENT);
        } catch (InvoicePaymentAdjustmentPending ex) {
            throw new InvoicePaymentAdjustmentPendingException();
        } catch (InvalidPaymentStatus | InvalidPaymentTargetStatus ex) {
            throw new InvoicingPaymentStatusRestrictionsException(ex, null);
        } catch (TException ex) {
            throw new InvoicingException(String.format("Failed to createPaymentAdjustment with id: %s", invoiceId), ex);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/service/external/impl/PartyManagementServiceImpl.java
MD5:  15aa34783e6c1233a60fe59ea5e6ddce
SHA1: 241f395937c347aab87be8fca5f6262bbf412150
package dev.vality.disputes.service.external.impl;

import dev.vality.damsel.domain.Party;
import dev.vality.damsel.domain.Shop;
import dev.vality.damsel.payment_processing.PartyManagementSrv;
import dev.vality.damsel.payment_processing.PartyNotFound;
import dev.vality.damsel.payment_processing.PartyRevisionParam;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.exception.PartyException;
import dev.vality.disputes.service.external.PartyManagementService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.thrift.TException;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class PartyManagementServiceImpl implements PartyManagementService {

    private final PartyManagementSrv.Iface partyManagementClient;

    public Shop getShop(String partyId, String shopId) {
        log.debug("Trying to get shop, partyId='{}', shopId='{}'", partyId, shopId);
        var party = getParty(partyId);
        var shop = party.getShops().get(shopId);
        if (shop == null) {
            throw new NotFoundException(
                    String.format("Shop not found, partyId='%s', shopId='%s'", partyId, shopId), NotFoundException.Type.SHOP);
        }
        log.debug("Shop has been found, partyId='{}', shopId='{}'", partyId, shopId);
        return shop;
    }

    private Party getParty(String partyId) {
        return getParty(partyId, getPartyRevision(partyId));
    }

    private Party getParty(String partyId, long partyRevision) {
        return getParty(partyId, PartyRevisionParam.revision(partyRevision));
    }

    private Party getParty(String partyId, PartyRevisionParam partyRevisionParam) {
        log.debug("Trying to get party, partyId='{}', partyRevisionParam='{}'", partyId, partyRevisionParam);
        try {
            var party = partyManagementClient.checkout(partyId, partyRevisionParam);
            log.debug("Party has been found, partyId='{}', partyRevisionParam='{}'", partyId, partyRevisionParam);
            return party;
        } catch (PartyNotFound ex) {
            throw new NotFoundException(
                    String.format("Party not found, partyId='%s', partyRevisionParam='%s'", partyId, partyRevisionParam), ex, NotFoundException.Type.PARTY);
        } catch (TException ex) {
            throw new PartyException(
                    String.format("Failed to get party, partyId='%s', partyRevisionParam='%s'", partyId, partyRevisionParam), ex);
        }
    }

    private long getPartyRevision(String partyId) {
        try {
            log.debug("Trying to get revision, partyId='{}'", partyId);
            var revision = partyManagementClient.getRevision(partyId);
            log.debug("Revision has been found, partyId='{}', revision='{}'", partyId, revision);
            return revision;
        } catch (PartyNotFound ex) {
            throw new NotFoundException(String.format("Party not found, partyId='%s'", partyId), ex, NotFoundException.Type.PARTY);
        } catch (TException ex) {
            throw new PartyException(String.format("Failed to get party revision, partyId='%s'", partyId), ex);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/service/external/impl/dominant/DominantAsyncService.java
MD5:  e5403ea7bbe105561ee51c83c75977b1
SHA1: 42c4cacf68b61e8502ca577f593dcb407395192e
package dev.vality.disputes.service.external.impl.dominant;

import dev.vality.damsel.domain.*;
import dev.vality.disputes.service.external.DominantService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.util.concurrent.CompletableFuture;

@Slf4j
@Service
@RequiredArgsConstructor
public class DominantAsyncService {

    private final DominantService dominantService;

    @Async("disputesAsyncServiceExecutor")
    public CompletableFuture<Currency> getCurrency(CurrencyRef currencyRef) {
        try {
            var currency = dominantService.getCurrency(currencyRef);
            return CompletableFuture.completedFuture(currency);
        } catch (Throwable ex) {
            return CompletableFuture.failedFuture(ex);
        }
    }

    @Async("disputesAsyncServiceExecutor")
    public CompletableFuture<Terminal> getTerminal(TerminalRef terminalRef) {
        try {
            var terminal = dominantService.getTerminal(terminalRef);
            return CompletableFuture.completedFuture(terminal);
        } catch (Throwable ex) {
            return CompletableFuture.failedFuture(ex);
        }
    }

    @Async("disputesAsyncServiceExecutor")
    public CompletableFuture<ProxyDefinition> getProxy(ProxyRef proxyRef) {
        try {
            var proxy = dominantService.getProxy(proxyRef);
            return CompletableFuture.completedFuture(proxy);
        } catch (Throwable ex) {
            return CompletableFuture.failedFuture(ex);
        }
    }

    @Async("disputesAsyncServiceExecutor")
    public CompletableFuture<Provider> getProvider(ProviderRef providerRef) {
        try {
            var provider = dominantService.getProvider(providerRef);
            return CompletableFuture.completedFuture(provider);
        } catch (Throwable ex) {
            return CompletableFuture.failedFuture(ex);
        }
    }
}


FILE: ./src/main/java/dev/vality/disputes/service/external/impl/dominant/DominantCacheServiceImpl.java
MD5:  35f689df4a389ac937e7904ad508e0fc
SHA1: 8d204bf3650da2615a829c8ba4859c11f8ce6757
package dev.vality.disputes.service.external.impl.dominant;

import dev.vality.damsel.domain.*;
import dev.vality.damsel.domain_config.Reference;
import dev.vality.damsel.domain_config.*;
import dev.vality.disputes.exception.DominantException;
import dev.vality.disputes.exception.NotFoundException;
import dev.vality.disputes.exception.NotFoundException.Type;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.thrift.TException;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
@SuppressWarnings({"LineLength"})
public class DominantCacheServiceImpl {

    private final RepositoryClientSrv.Iface dominantClient;

    @Cacheable(value = "currencies", key = "#currencyRef.symbolic_code", cacheManager = "currenciesCacheManager")
    public Currency getCurrency(CurrencyRef currencyRef) {
        return getCurrency(currencyRef, Reference.head(new Head()));
    }

    private Currency getCurrency(CurrencyRef currencyRef, Reference revisionReference) {
        log.debug("Trying to get currency, currencyRef='{}', revisionReference='{}'", currencyRef, revisionReference);
        try {
            var reference = new dev.vality.damsel.domain.Reference();
            reference.setCurrency(currencyRef);
            var versionedObject = checkoutObject(revisionReference, reference);
            var currency = versionedObject.getObject().getCurrency().getData();
            log.debug("Currency has been found, currencyRef='{}', revisionReference='{}'",
                    currencyRef, revisionReference);
            return currency;
        } catch (VersionNotFound | ObjectNotFound ex) {
            throw new NotFoundException(String.format("Version not found, currencyRef='%s', revisionReference='%s'", currencyRef, revisionReference), ex, Type.CURRENCY);
        } catch (TException ex) {
            throw new DominantException(String.format("Failed to get currency, currencyRef='%s', " +
                    "revisionReference='%s'", currencyRef, revisionReference), ex);
        }
    }

    @Cacheable(value = "terminals", key = "#terminalRef.id", cacheManager = "terminalsCacheManager")
    public Terminal getTerminal(TerminalRef terminalRef) {
        return getTerminal(terminalRef, Reference.head(new Head()));
    }

    public Terminal getTerminal(TerminalRef terminalRef, Reference revisionReference) {
        log.debug("Trying to get terminal from dominant, terminalRef='{}', revisionReference='{}'", terminalRef,
                revisionReference);
        try {
            var reference = new dev.vality.damsel.domain.Reference();
            reference.setTerminal(terminalRef);
            var versionedObject = checkoutObject(revisionReference, reference);
            var terminal = versionedObject.getObject().getTerminal().getData();
            log.debug("Terminal has been found, terminalRef='{}', revisionReference='{}'",
                    terminalRef, revisionReference);
            return terminal;
        } catch (VersionNotFound | ObjectNotFound ex) {
            throw new NotFoundException(String.format("Version not found, terminalRef='%s', revisionReference='%s'", terminalRef, revisionReference), ex, Type.TERMINAL);
        } catch (TException ex) {
            throw new DominantException(String.format("Failed to get terminal, terminalRef='%s'," +
                    " revisionReference='%s'", terminalRef, revisionReference), ex);
        }
    }

    @Cacheable(value = "providers", key = "#providerRef.id", cacheManager = "providersCacheManager")
    public Provider getProvider(ProviderRef providerRef) {
        return getProvider(providerRef, Reference.head(new Head()));
    }

    private Provider getProvider(ProviderRef providerRef, Reference revisionReference) {
        log.debug("Trying to get provider from dominant, providerRef='{}', revisionReference='{}'", providerRef,
                revisionReference);
        try {
            var reference = new dev.vality.damsel.domain.Reference();
            reference.setProvider(providerRef);
            var versionedObject = checkoutObject(revisionReference, reference);
            var provider = versionedObject.getObject().getProvider().getData();
            log.debug("Provider has been found, providerRef='{}', revisionReference='{}'",
                    providerRef, revisionReference);
            return provider;
        } catch (VersionNotFound | ObjectNotFound ex) {
            throw new NotFoundException(String.format("Version not found, providerRef='%s', revisionReference='%s'", providerRef, revisionReference), ex, Type.PROVIDER);
        } catch (TException ex) {
            throw new DominantException(String.format("Failed to get provider, providerRef='%s'," +
                    " revisionReference='%s'", providerRef, revisionReference), ex);
        }
    }

    @Cacheable(value = "proxies", key = "#proxyRef.id", cacheManager = "proxiesCacheManager")
    public ProxyDefinition getProxy(ProxyRef proxyRef) {
        return getProxy(proxyRef, Reference.head(new Head()));
    }


    private ProxyDefinition getProxy(ProxyRef proxyRef, Reference revisionReference) {
        log.debug("Trying to get proxy from dominant, proxyRef='{}', revisionReference='{}'", proxyRef,
                revisionReference);
        try {
            var reference = new dev.vality.damsel.domain.Reference();
            reference.setProxy(proxyRef);
            var versionedObject = checkoutObject(revisionReference, reference);
            var proxy = versionedObject.getObject().getProxy().getData();
            log.debug("Proxy has been found, proxyRef='{}', revisionReference='{}'", proxyRef, revisionReference);
            return proxy;
        } catch (VersionNotFound | ObjectNotFound ex) {
            throw new NotFoundException(String.format("Version not found, proxyRef='%s', revisionReference='%s'", proxyRef, revisionReference), ex, Type.PROXY);
        } catch (TException ex) {
            throw new DominantException(String.format("Failed to get proxy, proxyRef='%s', revisionReference='%s'",
                    proxyRef, revisionReference), ex);
        }
    }

    private VersionedObject checkoutObject(Reference revisionReference, dev.vality.damsel.domain.Reference reference) throws TException {
        return dominantClient.checkoutObject(revisionReference, reference);
    }
}


FILE: ./src/main/java/dev/vality/disputes/servlet/AdminManagementServlet.java
MD5:  6724a10a45bfa51d8bf00fa9949b1b5e
SHA1: dc0f26f571d65ad65a332713d460c799335b243c
package dev.vality.disputes.servlet;

import dev.vality.disputes.admin.AdminManagementServiceSrv;
import dev.vality.woody.thrift.impl.http.THServiceBuilder;
import jakarta.servlet.*;
import jakarta.servlet.annotation.WebServlet;
import org.springframework.beans.factory.annotation.Autowired;

import java.io.IOException;

@WebServlet("/v1/admin-management")
public class AdminManagementServlet extends GenericServlet {

    @Autowired
    private AdminManagementServiceSrv.Iface adminManagementHandler;

    private Servlet servlet;

    @Override
    public void init(ServletConfig config) throws ServletException {
        super.init(config);
        servlet = new THServiceBuilder()
                .build(AdminManagementServiceSrv.Iface.class, adminManagementHandler);
    }

    @Override
    public void service(ServletRequest request, ServletResponse response) throws ServletException, IOException {
        servlet.service(request, response);
    }
}


FILE: ./src/main/java/dev/vality/disputes/servlet/MerchantServlet.java
MD5:  e354f2254ba6be24d031697bf17a537b
SHA1: 62dcf6f538ab23b5799b91f807ea0e0ed4c4a88b
package dev.vality.disputes.servlet;

import dev.vality.disputes.merchant.MerchantDisputesServiceSrv;
import dev.vality.woody.thrift.impl.http.THServiceBuilder;
import jakarta.servlet.*;
import jakarta.servlet.annotation.WebServlet;
import org.springframework.beans.factory.annotation.Autowired;

import java.io.IOException;

@WebServlet("/v1/merchant")
public class MerchantServlet extends GenericServlet {

    @Autowired
    private MerchantDisputesServiceSrv.Iface merchantDisputesHandler;

    private Servlet servlet;

    @Override
    public void init(ServletConfig config) throws ServletException {
        super.init(config);
        servlet = new THServiceBuilder()
                .build(MerchantDisputesServiceSrv.Iface.class, merchantDisputesHandler);
    }

    @Override
    public void service(ServletRequest request, ServletResponse response) throws ServletException, IOException {
        servlet.service(request, response);
    }
}


FILE: ./src/main/java/dev/vality/disputes/util/ErrorFormatter.java
MD5:  8f0adb8bb8f1213d068baa4964c8721a
SHA1: 674b65da1e1aa5ced47ecbb36b1cf1d87eb0ce45
package dev.vality.disputes.util;

import dev.vality.damsel.domain.Failure;
import dev.vality.geck.serializer.kit.tbase.TErrorUtil;
import lombok.experimental.UtilityClass;
import org.apache.commons.lang3.StringUtils;

import java.util.Base64;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@UtilityClass
public class ErrorFormatter {

    public static String getErrorMessage(Failure failure) {
        return decodeFragment(getDefaultErrorMessage(failure));
    }

    public static String getErrorMessage(String errorCode, String errorDescription) {
        return decodeFragment(getDefaultErrorMessage(errorCode, errorDescription));
    }

    private static String getDefaultErrorMessage(Failure failure) {
        if (!StringUtils.isBlank(failure.getReason())) {
            return failure.getCode() + ": " + failure.getReason();
        }
        return TErrorUtil.toStringVal(failure);
    }

    private static String getDefaultErrorMessage(String errorCode, String errorDescription) {
        if (!StringUtils.isBlank(errorDescription)) {
            return errorCode + ": " + errorDescription;
        }
        return errorCode;
    }

    private static String decodeFragment(String errorMessage) {
        if (!errorMessage.contains("base64:")) {
            return errorMessage;
        }
        var pattern = Pattern.compile("base64:([A-Za-z0-9+/=]+)");
        var matcher = pattern.matcher(errorMessage);
        var result = new StringBuilder();
        while (matcher.find()) {
            var base64String = matcher.group(1);
            var decodedBytes = Base64.getDecoder().decode(base64String);
            var decodedString = new String(decodedBytes);
            matcher.appendReplacement(result, Matcher.quoteReplacement(decodedString));
        }
        matcher.appendTail(result);
        return result.toString();
    }
}


FILE: ./src/main/java/dev/vality/disputes/util/OptionsExtractor.java
MD5:  fdcf2c04ccf588f06cabba821bc7b561
SHA1: 3a9097e6fa3e91ac8eed80a3a50cfa2758aa1456
package dev.vality.disputes.util;

import dev.vality.damsel.domain.Provider;
import dev.vality.damsel.domain.ProxyDefinition;
import dev.vality.damsel.domain.Terminal;
import lombok.experimental.UtilityClass;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import static dev.vality.disputes.constant.TerminalOptionsField.DISPUTE_FLOW_MAX_TIME_POLLING_MIN;

@UtilityClass
public class OptionsExtractor {

    public static Integer extractMaxTimePolling(Map<String, String> options, int maxTimePolling) {
        return Integer.parseInt(
                options.getOrDefault(DISPUTE_FLOW_MAX_TIME_POLLING_MIN, String.valueOf(maxTimePolling)));
    }

    public static Map<String, String> mergeOptions(Provider provider, ProxyDefinition proxy, Terminal terminal) {
        var merged = new HashMap<String, String>();
        merged.putAll(safetyPut(provider.getProxy().getAdditional()));
        merged.putAll(safetyPut(proxy.getOptions()));
        merged.putAll(safetyPut(terminal.getOptions()));
        return merged;
    }

    private static Map<String, String> safetyPut(Map<String, String> options) {
        return Optional.ofNullable(options)
                .orElse(new HashMap<>());
    }
}


FILE: ./src/main/java/dev/vality/disputes/util/PaymentAmountUtil.java
MD5:  c12f4baea222b27b8f8c480abf5fd6c1
SHA1: 73311095682a8feba54569f1627da3245b9138dd
package dev.vality.disputes.util;

import dev.vality.damsel.domain.Cash;
import dev.vality.damsel.domain.InvoicePayment;
import lombok.experimental.UtilityClass;

import java.util.Optional;

@UtilityClass
public class PaymentAmountUtil {

    public static Long getChangedAmount(InvoicePayment payment) {
        return Optional.ofNullable(payment.getChangedCost())
                .map(Cash::getAmount)
                .filter(a -> payment.getCost().getAmount() != a)
                .orElse(null);
    }
}


FILE: ./src/main/java/dev/vality/disputes/util/PaymentStatusValidator.java
MD5:  2e4203afa2d435e6ec67cf3670cb6b65
SHA1: b7c5d448f5dd54925d5205acd93509e35a62eaa6
package dev.vality.disputes.util;

import dev.vality.damsel.payment_processing.InvoicePayment;
import dev.vality.disputes.constant.ErrorMessage;
import dev.vality.disputes.exception.CapturedPaymentException;
import dev.vality.disputes.exception.InvoicingPaymentStatusRestrictionsException;
import lombok.experimental.UtilityClass;

@UtilityClass
@SuppressWarnings({"LineLength"})
public class PaymentStatusValidator {

    public static void checkStatus(InvoicePayment invoicePayment) {
        var invoicePaymentStatus = invoicePayment.getPayment().getStatus();
        switch (invoicePaymentStatus.getSetField()) {
            case CAPTURED -> throw new CapturedPaymentException(invoicePayment);
            case FAILED, CANCELLED -> {
            }
            default -> throw new InvoicingPaymentStatusRestrictionsException(invoicePaymentStatus);
        }
    }

    public static String getInvoicingPaymentStatusRestrictionsErrorReason(InvoicingPaymentStatusRestrictionsException ex) {
        if (ex.getStatus() != null) {
            return ErrorMessage.PAYMENT_STATUS_RESTRICTIONS + ": " + ex.getStatus().getSetField().getFieldName();
        }
        return ErrorMessage.PAYMENT_STATUS_RESTRICTIONS;
    }
}


FILE: ./src/test/java/dev/vality/disputes/admin/management/DebugAdminManagementController.java
MD5:  4d54f8e3129086d391687436572c8344
SHA1: 31c1f8c288811c56b94cff672d9c32e99365d15e
package dev.vality.disputes.admin.management;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.JsonDeserializer;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import com.fasterxml.jackson.datatype.jdk8.Jdk8Module;
import dev.vality.disputes.admin.*;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

@RestController
@RequiredArgsConstructor
@RequestMapping({"/debug/v1/admin-management"})
@Slf4j
@SuppressWarnings({"LineLength"})
public class DebugAdminManagementController {

    private final AdminManagementServiceSrv.Iface adminManagementHandler;
    private final ObjectMapper objectMapper = new ObjectMapper().registerModule(new Jdk8Module());

    @PostMapping("/cancel")
    @SneakyThrows
    public void cancelPending(@RequestBody String body) {
        log.debug("cancelPending {}", body);
        adminManagementHandler.cancelPending(objectMapper.readValue(body, CancelParamsRequest.class));
    }

    @PostMapping("/approve")
    @SneakyThrows
    public void approvePending(@RequestBody String body) {
        log.debug("approvePending {}", body);
        adminManagementHandler.approvePending(objectMapper.readValue(body, ApproveParamsRequest.class));
    }

    @PostMapping("/bind")
    @SneakyThrows
    public void bindCreated(@RequestBody String body) {
        log.debug("bindCreated {}", body);
        adminManagementHandler.bindCreated(objectMapper.readValue(body, BindParamsRequest.class));
    }

    @PostMapping("/get")
    @SneakyThrows
    public DisputeResult getDisputes(@RequestBody String body) {
        log.debug("getDispute {}", body);
        var dispute = adminManagementHandler.getDisputes(objectMapper.readValue(body, DisputeParamsRequest.class));
        return objectMapper.convertValue(dispute, new TypeReference<>() {
        });
    }

    @PostMapping("/pooling-expired")
    @SneakyThrows
    public void setPendingForPoolingExpired(@RequestBody String body) {
        log.debug("setPendingForPoolingExpired {}", body);
        adminManagementHandler.setPendingForPoolingExpired(objectMapper.readValue(body, SetPendingForPoolingExpiredParamsRequest.class));
    }

    @GetMapping("/disputes")
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public void defaultRouteUrl() {
        log.info("hi");
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class DisputeResult {

        @JsonProperty("disputes")
        private List<Dispute> disputes;
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class Dispute {

        @JsonProperty("disputeId")
        private String disputeId; // required
        @JsonProperty("providerDisputeId")
        private String providerDisputeId; // optional
        @JsonProperty("invoiceId")
        private String invoiceId; // required
        @JsonProperty("paymentId")
        private String paymentId; // required
        @JsonProperty("providerTrxId")
        private String providerTrxId; // required
        @JsonProperty("status")
        private String status; // required
        @JsonProperty("errorMessage")
        private String errorMessage; // optional
        @JsonProperty("amount")
        private String amount; // required
        @JsonProperty("changedAmount")
        private String changedAmount; // optional
        @JsonProperty("skipCallHgForCreateAdjustment")
        private boolean skipCallHgForCreateAdjustment; // required
        @JsonProperty("attachments")
        @JsonDeserialize(using = AttachmentsDeserializer.class)
        public List<Attachment> attachments;
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class Attachment {

        private String data;

    }

    public static class AttachmentsDeserializer extends JsonDeserializer<List<Attachment>> {

        @Override
        public List<Attachment> deserialize(JsonParser parser, DeserializationContext ctxt) throws IOException {
            var node = (JsonNode) parser.getCodec().readTree(parser);
            if (node.isArray()) {
                var attachments = new ArrayList<Attachment>();
                for (JsonNode jsonNode : node) {
                    if (jsonNode.isObject()) {
                        var data = jsonNode.get("data");
                        if (data.isBinary()) {
                            var attachmentResult = new Attachment();
                            attachmentResult.setData(Base64.getEncoder().encodeToString(data.binaryValue().clone()));
                            attachments.add(attachmentResult);
                        }
                    }
                }
                return attachments;
            }
            return null;
        }
    }
}


FILE: ./src/test/java/dev/vality/disputes/admin/management/DebugAdminManagementControllerTest.java
MD5:  ddeeb24e1da3da3fcfe133d34e482590
SHA1: 6ee2975a6bd0c0df7de82ec7826b1d0c15644a65
package dev.vality.disputes.admin.management;

import dev.vality.disputes.admin.AdminManagementServiceSrv;
import dev.vality.disputes.admin.Attachment;
import dev.vality.disputes.admin.Dispute;
import dev.vality.disputes.admin.DisputeResult;
import dev.vality.disputes.config.SpringBootUTest;
import lombok.SneakyThrows;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.util.List;
import java.util.Random;

import static dev.vality.testcontainers.annotations.util.RandomBeans.randomThrift;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;

@SpringBootUTest
public class DebugAdminManagementControllerTest {

    @MockitoBean
    private AdminManagementServiceSrv.Iface adminManagementHandler;
    @Autowired
    private DebugAdminManagementController debugAdminManagementController;

    @Test
    @SneakyThrows
    public void checkSerialization() {
        debugAdminManagementController.approvePending("""
                {
                  "approveParams": [
                    {
                      "invoiceId": "asd",
                      "paymentId": "asd",
                      "skipCallHgForCreateAdjustment": true
                    }
                  ]
                }
                """);
        debugAdminManagementController.cancelPending("""
                {
                  "cancelParams": [
                    {
                      "invoiceId": "asd",
                      "paymentId": "asd",
                      "cancelReason": "test endpoint"
                    }
                  ]
                }
                """);
        debugAdminManagementController.cancelPending("""
                {
                  "cancelParams": [
                    {
                      "invoiceId": "asd",
                      "paymentId": "asd",
                      "cancelReason": "test endpoint"
                    }
                  ]
                }
                """);
        debugAdminManagementController.bindCreated("""
                  {
                    "bindParams": [
                      {
                        "disputeId": "36",
                        "providerDisputeId": "66098"
                      }
                    ]
                  }
                """);
        var randomed = new DisputeResult();
        byte[] b = new byte[20];
        new Random().nextBytes(b);
        byte[] a = new byte[20];
        new Random().nextBytes(a);
        randomed.setDisputes(List.of(
                randomThrift(Dispute.class).setAttachments(List.of(new Attachment().setData(b))),
                randomThrift(Dispute.class).setAttachments(List.of(new Attachment().setData(a)))));
        given(adminManagementHandler.getDisputes(any()))
                .willReturn(randomed);
        var disputes = debugAdminManagementController.getDisputes("""
                  {
                    "disputeParams": [
                      {
                      "invoiceId": "asd",
                      "paymentId": "asd"
                      }
                    ],
                    "withAttachments": false
                  }
                """);
        assertEquals(2, disputes.getDisputes().size());
    }
}


FILE: ./src/test/java/dev/vality/disputes/admin/management/DebugAdminManagementHandlerTest.java
MD5:  cdd61970039ed0c77c7bcd59299e6a00
SHA1: c7b8f293ac7ce55031daf7cb73b4ca44286d192a
package dev.vality.disputes.admin.management;

import dev.vality.disputes.config.AbstractMockitoConfig;
import dev.vality.disputes.config.WireMockSpringBootITest;
import dev.vality.disputes.constant.ErrorMessage;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.util.WiremockUtils;
import dev.vality.provider.payments.PaymentStatusResult;
import dev.vality.provider.payments.ProviderPaymentsServiceSrv;
import lombok.SneakyThrows;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.UUID;

import static dev.vality.disputes.util.MockUtil.*;
import static dev.vality.disputes.util.OpenApiUtil.*;
import static dev.vality.testcontainers.annotations.util.ValuesGenerator.generateId;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@WireMockSpringBootITest
@SuppressWarnings({"LineLength"})
public class DebugAdminManagementHandlerTest extends AbstractMockitoConfig {

    @Autowired
    private DebugAdminManagementController debugAdminManagementController;

    @Test
    public void testCancelCreateAdjustment() {
        var disputeId = pendingFlowHandler.handlePending();
        var dispute = disputeDao.get(disputeId);
        debugAdminManagementController.cancelPending(getCancelRequest(dispute.getInvoiceId(), dispute.getPaymentId()));
        assertEquals(DisputeStatus.cancelled, disputeDao.get(disputeId).getStatus());
    }

    @Test
    public void testCancelPending() {
        var disputeId = createdFlowHandler.handleCreate();
        var dispute = disputeDao.get(disputeId);
        debugAdminManagementController.cancelPending(getCancelRequest(dispute.getInvoiceId(), dispute.getPaymentId()));
        assertEquals(DisputeStatus.cancelled, disputeDao.get(disputeId).getStatus());
    }

    @Test
    public void testCancelFailed() {
        var disputeId = pendingFlowHandler.handlePending();
        disputeDao.finishFailed(disputeId, null);
        var dispute = disputeDao.get(disputeId);
        debugAdminManagementController.cancelPending(getCancelRequest(dispute.getInvoiceId(), dispute.getPaymentId()));
        assertEquals(DisputeStatus.failed, disputeDao.get(disputeId).getStatus());
    }

    @Test
    public void testApproveCreateAdjustmentWithCallHg() {
        var disputeId = pendingFlowHandler.handlePending();
        var dispute = disputeDao.get(disputeId);
        debugAdminManagementController.approvePending(getApproveRequest(dispute.getInvoiceId(), dispute.getPaymentId(), false));
        assertEquals(DisputeStatus.succeeded, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    public void testApproveCreateAdjustmentWithSkipHg() {
        var disputeId = pendingFlowHandler.handlePending();
        var dispute = disputeDao.get(disputeId);
        debugAdminManagementController.approvePending(getApproveRequest(dispute.getInvoiceId(), dispute.getPaymentId(), true));
        assertEquals(DisputeStatus.succeeded, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testApprovePendingWithCallHg() {
        var disputeId = createdFlowHandler.handleCreate();
        var providerPaymentMock = mock(ProviderPaymentsServiceSrv.Client.class);
        when(providerPaymentMock.checkPaymentStatus(any(), any())).thenReturn(new PaymentStatusResult(true));
        when(providerPaymentsThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerPaymentMock);
        var dispute = disputeDao.get(disputeId);
        debugAdminManagementController.approvePending(getApproveRequest(dispute.getInvoiceId(), dispute.getPaymentId(), false));
        assertEquals(DisputeStatus.create_adjustment, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    public void testApprovePendingWithSkipHg() {
        var disputeId = createdFlowHandler.handleCreate();
        var dispute = disputeDao.get(disputeId);
        debugAdminManagementController.approvePending(getApproveRequest(dispute.getInvoiceId(), dispute.getPaymentId(), true));
        assertEquals(DisputeStatus.succeeded, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    public void testApproveFailed() {
        var disputeId = pendingFlowHandler.handlePending();
        disputeDao.finishFailed(disputeId, null);
        var dispute = disputeDao.get(disputeId);
        debugAdminManagementController.approvePending(getApproveRequest(dispute.getInvoiceId(), dispute.getPaymentId(), true));
        assertEquals(DisputeStatus.failed, disputeDao.get(disputeId).getStatus());
    }

    @Test
    public void testBindCreatedCreateAdjustment() {
        var disputeId = pendingFlowHandler.handlePending();
        var providerDisputeId = generateId();
        debugAdminManagementController.bindCreated(getBindCreatedRequest(disputeId, providerDisputeId));
        assertEquals(DisputeStatus.create_adjustment, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    public void testBindCreatedPending() {
        var disputeId = createdFlowHandler.handleCreate();
        var providerDisputeId = generateId();
        debugAdminManagementController.bindCreated(getBindCreatedRequest(disputeId, providerDisputeId));
        assertEquals(DisputeStatus.pending, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testBindCreatedAlreadyExist() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        disputeDao.setNextStepToAlreadyExist(disputeId);
        when(dominantService.getTerminal(any())).thenReturn(createTerminal().get());
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy().get());
        debugAdminManagementController.bindCreated(getBindCreatedRequest(disputeId, generateId()));
        assertEquals(DisputeStatus.pending, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testGetDispute() {
        WiremockUtils.mockS3AttachmentDownload();
        var disputeId = pendingFlowHandler.handlePending();
        var dispute = disputeDao.get(disputeId);
        var disputes = debugAdminManagementController.getDisputes(getGetDisputeRequest(dispute.getInvoiceId(), dispute.getPaymentId(), true));
        assertEquals(1, disputes.getDisputes().size());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testSetPendingForPoolingExpiredDispute() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        disputeDao.setNextStepToPoolingExpired(disputeId, ErrorMessage.POOLING_EXPIRED);
        when(dominantService.getTerminal(any())).thenReturn(createTerminal().get());
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy().get());
        var dispute = disputeDao.get(disputeId);
        debugAdminManagementController.setPendingForPoolingExpired(getSetPendingForPoolingExpiredParamsRequest(dispute.getInvoiceId(), dispute.getPaymentId()));
        assertEquals(DisputeStatus.pending, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }
}


FILE: ./src/test/java/dev/vality/disputes/api/DisputesApiDelegateServiceTest.java
MD5:  a5b5784615dfc5afb106d7468d77e9ea
SHA1: b65c1587bb7129c40952ef9386c17dd654ccaafe
package dev.vality.disputes.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.vality.bouncer.decisions.ArbiterSrv;
import dev.vality.damsel.payment_processing.InvoicingSrv;
import dev.vality.disputes.config.WireMockSpringBootITest;
import dev.vality.disputes.config.WiremockAddressesHolder;
import dev.vality.disputes.dao.DisputeDao;
import dev.vality.disputes.service.external.PartyManagementService;
import dev.vality.disputes.service.external.impl.dominant.DominantAsyncService;
import dev.vality.disputes.util.MockUtil;
import dev.vality.disputes.util.OpenApiUtil;
import dev.vality.disputes.util.WiremockUtils;
import dev.vality.file.storage.FileStorageSrv;
import dev.vality.swag.disputes.model.Create200Response;
import dev.vality.token.keeper.TokenAuthenticatorSrv;
import lombok.SneakyThrows;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.MockitoAnnotations;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.UUID;

import static dev.vality.disputes.util.MockUtil.*;
import static java.util.UUID.randomUUID;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WireMockSpringBootITest
@SuppressWarnings({"LineLength"})
public class DisputesApiDelegateServiceTest {

    @MockitoBean
    private InvoicingSrv.Iface invoicingClient;
    @MockitoBean
    private TokenAuthenticatorSrv.Iface tokenKeeperClient;
    @MockitoBean
    private ArbiterSrv.Iface bouncerClient;
    @MockitoBean
    private DominantAsyncService dominantAsyncService;
    @MockitoBean
    private PartyManagementService partyManagementService;
    @MockitoBean
    private FileStorageSrv.Iface fileStorageClient;
    @Autowired
    private MockMvc mvc;
    @Autowired
    private DisputeDao disputeDao;
    @Autowired
    private WiremockAddressesHolder wiremockAddressesHolder;
    private AutoCloseable mocks;
    private Object[] preparedMocks;

    @BeforeEach
    public void init() {
        mocks = MockitoAnnotations.openMocks(this);
        preparedMocks = new Object[]{invoicingClient, tokenKeeperClient, bouncerClient,
                fileStorageClient, dominantAsyncService, partyManagementService};
    }

    @AfterEach
    public void clean() throws Exception {
        verifyNoMoreInteractions(preparedMocks);
        mocks.close();
    }

    @Test
    @SneakyThrows
    void testFullApiFlowSuccess() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        when(invoicingClient.get(any(), any()))
                .thenReturn(MockUtil.createInvoice(invoiceId, paymentId));
        when(tokenKeeperClient.authenticate(any(), any())).thenReturn(createAuthData());
        when(bouncerClient.judge(any(), any())).thenReturn(createJudgementAllowed());
        when(dominantAsyncService.getTerminal(any())).thenReturn(createTerminal());
        when(dominantAsyncService.getCurrency(any())).thenReturn(createCurrency());
        when(dominantAsyncService.getProvider(any())).thenReturn(createProvider());
        when(dominantAsyncService.getProxy(any())).thenReturn(createProxy());
        when(partyManagementService.getShop(any(), any())).thenReturn(createShop());
        when(fileStorageClient.createNewFile(any(), any())).thenReturn(createNewFileResult(wiremockAddressesHolder.getUploadUrl()));
        WiremockUtils.mockS3AttachmentUpload();
        var resultActions = mvc.perform(post("/disputes/create")
                        .header("Authorization", "Bearer token")
                        .header("X-Request-ID", randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(OpenApiUtil.getContentCreateRequest(invoiceId, paymentId)))
                .andExpect(status().is2xxSuccessful())
                .andExpect(jsonPath("$.disputeId").isNotEmpty());
        var response = new ObjectMapper().readValue(resultActions.andReturn().getResponse().getContentAsString(), Create200Response.class);
        verify(invoicingClient, times(1)).get(any(), any());
        verify(tokenKeeperClient, times(1)).authenticate(any(), any());
        verify(bouncerClient, times(1)).judge(any(), any());
        verify(dominantAsyncService, times(1)).getTerminal(any());
        verify(dominantAsyncService, times(1)).getCurrency(any());
        verify(dominantAsyncService, times(1)).getProvider(any());
        verify(dominantAsyncService, times(1)).getProxy(any());
        verify(partyManagementService, times(1)).getShop(any(), any());
        verify(fileStorageClient, times(1)).createNewFile(any(), any());
        mvc.perform(get("/disputes/status")
                        .header("Authorization", "Bearer token")
                        .header("X-Request-ID", randomUUID())
                        .params(OpenApiUtil.getStatusRequiredParams(response.getDisputeId(), invoiceId, paymentId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(""))
                .andExpect(status().is2xxSuccessful())
                .andExpect(jsonPath("$.status").isNotEmpty());
        verify(invoicingClient, times(2)).get(any(), any());
        verify(tokenKeeperClient, times(2)).authenticate(any(), any());
        verify(bouncerClient, times(2)).judge(any(), any());
        // exist
        resultActions = mvc.perform(post("/disputes/create")
                        .header("Authorization", "Bearer token")
                        .header("X-Request-ID", randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(OpenApiUtil.getContentCreateRequest(invoiceId, paymentId)))
                .andExpect(status().is2xxSuccessful())
                .andExpect(jsonPath("$.disputeId").isNotEmpty());
        assertEquals(response.getDisputeId(), new ObjectMapper().readValue(resultActions.andReturn().getResponse().getContentAsString(), Create200Response.class).getDisputeId());
        verify(invoicingClient, times(3)).get(any(), any());
        verify(tokenKeeperClient, times(3)).authenticate(any(), any());
        verify(bouncerClient, times(3)).judge(any(), any());
        disputeDao.finishFailed(UUID.fromString(response.getDisputeId()), null);
        // new after failed
        when(fileStorageClient.createNewFile(any(), any())).thenReturn(createNewFileResult(wiremockAddressesHolder.getUploadUrl()));
        resultActions = mvc.perform(post("/disputes/create")
                        .header("Authorization", "Bearer token")
                        .header("X-Request-ID", randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(OpenApiUtil.getContentCreateRequest(invoiceId, paymentId)))
                .andExpect(status().is2xxSuccessful())
                .andExpect(jsonPath("$.disputeId").isNotEmpty());
        assertNotEquals(response.getDisputeId(), new ObjectMapper().readValue(resultActions.andReturn().getResponse().getContentAsString(), Create200Response.class).getDisputeId());
        verify(invoicingClient, times(4)).get(any(), any());
        verify(tokenKeeperClient, times(4)).authenticate(any(), any());
        verify(bouncerClient, times(4)).judge(any(), any());
        verify(dominantAsyncService, times(2)).getTerminal(any());
        verify(dominantAsyncService, times(2)).getCurrency(any());
        verify(dominantAsyncService, times(2)).getProvider(any());
        verify(dominantAsyncService, times(2)).getProxy(any());
        verify(partyManagementService, times(2)).getShop(any(), any());
        verify(fileStorageClient, times(2)).createNewFile(any(), any());
        disputeDao.finishFailed(UUID.fromString(response.getDisputeId()), null);
    }

    @Test
    @SneakyThrows
    void testBadRequestWhenInvalidCreateRequest() {
        var paymentId = "1";
        mvc.perform(post("/disputes/create")
                        .header("Authorization", "Bearer token")
                        .header("X-Request-ID", randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(OpenApiUtil.getContentInvalidCreateRequest(paymentId)))
                .andExpect(status().is4xxClientError());
    }

    @Test
    @SneakyThrows
    void testNotFoundWhenUnknownDisputeId() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        mvc.perform(get("/disputes/status")
                        .header("Authorization", "Bearer token")
                        .header("X-Request-ID", randomUUID())
                        .params(OpenApiUtil.getStatusRequiredParams(randomUUID().toString(), invoiceId, paymentId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(""))
                .andExpect(status().is4xxClientError());
    }
}


FILE: ./src/test/java/dev/vality/disputes/api/ServletTest.java
MD5:  ee5387197867a936a58059f8d6afd1fb
SHA1: 37196a7569a9ba118ce2f7eb69bd1cdbb35b5b36
package dev.vality.disputes.api;

import dev.vality.damsel.payment_processing.InvoicingSrv;
import dev.vality.disputes.admin.AdminManagementServiceSrv;
import dev.vality.disputes.admin.CancelParamsRequest;
import dev.vality.disputes.config.WireMockSpringBootITest;
import dev.vality.disputes.merchant.DisputeParams;
import dev.vality.disputes.merchant.MerchantDisputesServiceSrv;
import dev.vality.disputes.util.DamselUtil;
import dev.vality.provider.payments.ProviderPaymentsCallbackParams;
import dev.vality.provider.payments.ProviderPaymentsCallbackServiceSrv;
import dev.vality.woody.api.flow.error.WRuntimeException;
import dev.vality.woody.thrift.impl.http.THSpawnClientBuilder;
import lombok.SneakyThrows;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.net.URI;

import static dev.vality.disputes.config.NetworkConfig.*;

@WireMockSpringBootITest
@TestPropertySource(properties = {
"server.port=${local.server.port}"})
public class ServletTest {

    @MockitoBean
    private InvoicingSrv.Iface invoicingClient;
    @LocalServerPort
    private int serverPort;

    @Test
    @SneakyThrows
    public void merchantServletTest() {
        var iface = new THSpawnClientBuilder()
                .withAddress(new URI("http://127.0.0.1:" + serverPort + MERCHANT))
                .withNetworkTimeout(5000)
                .build(MerchantDisputesServiceSrv.Iface.class);
        var request = DamselUtil.fillRequiredTBaseObject(
                new DisputeParams(),
                DisputeParams.class
        );
        Assertions.assertThrows(WRuntimeException.class, () -> iface.createDispute(request));
    }

    @Test
    @SneakyThrows
    public void adminManagementServletTest() {
        var iface = new THSpawnClientBuilder()
                .withAddress(new URI("http://127.0.0.1:" + serverPort + ADMIN_MANAGEMENT))
                .withNetworkTimeout(5000)
                .build(AdminManagementServiceSrv.Iface.class);
        var request = DamselUtil.fillRequiredTBaseObject(
                new CancelParamsRequest(),
                CancelParamsRequest.class
        );
        iface.cancelPending(request);
    }

    @Test
    @SneakyThrows
    public void callbackServletTest() {
        var iface = new THSpawnClientBuilder()
                .withAddress(new URI("http://127.0.0.1:" + serverPort + CALLBACK))
                .withNetworkTimeout(5000)
                .build(ProviderPaymentsCallbackServiceSrv.Iface.class);
        var request = DamselUtil.fillRequiredTBaseObject(
                new ProviderPaymentsCallbackParams(),
                ProviderPaymentsCallbackParams.class
        );
        iface.createAdjustmentWhenFailedPaymentSuccess(request);
    }

    @Test
    @SneakyThrows
    public void wrongPathServletTest() {
        var iface = new THSpawnClientBuilder()
                .withAddress(new URI("http://127.0.0.1:" + serverPort + "/wrong_path"))
                .withNetworkTimeout(5000)
                .build(MerchantDisputesServiceSrv.Iface.class);
        var request = DamselUtil.fillRequiredTBaseObject(
                new DisputeParams(),
                DisputeParams.class
        );
        Assertions.assertThrows(WRuntimeException.class, () -> iface.createDispute(request));
    }
}


FILE: ./src/test/java/dev/vality/disputes/config/AbstractMockitoConfig.java
MD5:  4f6e9c8115adb185250b1adc926878c3
SHA1: 3a4088eb04a9ee5918dd1c147799096c6992d7d6
package dev.vality.disputes.config;

import dev.vality.bouncer.decisions.ArbiterSrv;
import dev.vality.damsel.payment_processing.InvoicingSrv;
import dev.vality.disputes.dao.DisputeDao;
import dev.vality.disputes.provider.payments.dao.ProviderCallbackDao;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsAdjustmentExtractor;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsService;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsThriftInterfaceBuilder;
import dev.vality.disputes.schedule.core.CreatedDisputesService;
import dev.vality.disputes.schedule.core.PendingDisputesService;
import dev.vality.disputes.schedule.service.ProviderDisputesThriftInterfaceBuilder;
import dev.vality.disputes.schedule.service.config.CreatedFlowHandler;
import dev.vality.disputes.schedule.service.config.MerchantApiMvcPerformer;
import dev.vality.disputes.schedule.service.config.PendingFlowHandler;
import dev.vality.disputes.schedule.service.config.ProviderCallbackFlowHandler;
import dev.vality.disputes.service.external.DominantService;
import dev.vality.disputes.service.external.PartyManagementService;
import dev.vality.disputes.service.external.impl.dominant.DominantAsyncService;
import dev.vality.file.storage.FileStorageSrv;
import dev.vality.token.keeper.TokenAuthenticatorSrv;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;

@SuppressWarnings({"LineLength"})
public abstract class AbstractMockitoConfig {

    @MockitoSpyBean
    public ProviderCallbackDao providerCallbackDao;

    @MockitoBean
    public InvoicingSrv.Iface invoicingClient;
    @MockitoBean
    public TokenAuthenticatorSrv.Iface tokenKeeperClient;
    @MockitoBean
    public ArbiterSrv.Iface bouncerClient;
    @MockitoBean
    public FileStorageSrv.Iface fileStorageClient;
    @MockitoBean
    public DominantService dominantService;
    @MockitoBean
    public DominantAsyncService dominantAsyncService;
    @MockitoBean
    public PartyManagementService partyManagementService;
    @MockitoBean
    public ProviderDisputesThriftInterfaceBuilder providerDisputesThriftInterfaceBuilder;
    @MockitoBean
    public ProviderPaymentsThriftInterfaceBuilder providerPaymentsThriftInterfaceBuilder;

    @Autowired
    public DisputeDao disputeDao;
    @Autowired
    public MockMvc mvc;
    @Autowired
    public WiremockAddressesHolder wiremockAddressesHolder;
    @Autowired
    public CreatedDisputesService createdDisputesService;
    @Autowired
    public PendingDisputesService pendingDisputesService;
    @Autowired
    public ProviderPaymentsService providerPaymentsService;
    @Autowired
    public ProviderPaymentsAdjustmentExtractor providerPaymentsAdjustmentExtractor;

    @LocalServerPort
    public int serverPort;

    public MerchantApiMvcPerformer merchantApiMvcPerformer;
    public CreatedFlowHandler createdFlowHandler;
    public PendingFlowHandler pendingFlowHandler;
    public ProviderCallbackFlowHandler providerCallbackFlowHandler;

    @BeforeEach
    void setUp() {
        merchantApiMvcPerformer = new MerchantApiMvcPerformer(invoicingClient, tokenKeeperClient, bouncerClient, fileStorageClient, dominantAsyncService, partyManagementService, wiremockAddressesHolder, mvc);
        createdFlowHandler = new CreatedFlowHandler(invoicingClient, fileStorageClient, disputeDao, dominantService, createdDisputesService, providerDisputesThriftInterfaceBuilder, providerPaymentsThriftInterfaceBuilder, wiremockAddressesHolder, merchantApiMvcPerformer);
        pendingFlowHandler = new PendingFlowHandler(disputeDao, providerCallbackDao, createdFlowHandler, pendingDisputesService, providerDisputesThriftInterfaceBuilder, providerPaymentsThriftInterfaceBuilder);
        providerCallbackFlowHandler = new ProviderCallbackFlowHandler(invoicingClient, disputeDao, providerCallbackDao, pendingFlowHandler, providerPaymentsService, providerPaymentsAdjustmentExtractor);
    }
}


FILE: ./src/test/java/dev/vality/disputes/config/DisableFlyway.java
MD5:  c3b77a0afe64e02734f574c322fb3640
SHA1: 89a621124e3e97246f0d2755d128e49adc304dab
package dev.vality.disputes.config;

import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import javax.sql.DataSource;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target({ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@TestPropertySource(properties = {
"spring.flyway.enabled=false",
})
@MockitoBean(types = {DataSource.class})
public @interface DisableFlyway {
}


FILE: ./src/test/java/dev/vality/disputes/config/DisableScheduling.java
MD5:  7e43236f5b30dfc1ee1a19626537264d
SHA1: 3f3334cd4c2d9dc5a6f1c6a5a05d697f3b8329ce
package dev.vality.disputes.config;

import org.springframework.test.context.TestPropertySource;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target({ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@TestPropertySource(properties = {
"dispute.isScheduleCreatedEnabled=false",
"dispute.isSchedulePendingEnabled=false",
"dispute.isScheduleForgottenEnabled=false",
"provider.payments.isScheduleCreateAdjustmentsEnabled=false",
})
public @interface DisableScheduling {
}


FILE: ./src/test/java/dev/vality/disputes/config/EmbeddedPostgresWithFlyway.java
MD5:  153be380c35ddb41b59376bcf48dc33f
SHA1: 313919716925aa573b2a71636bedb8879aeaadc3
package dev.vality.disputes.config;

import org.springframework.context.annotation.Import;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target({ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@Import(EmbeddedPostgresWithFlywayConfiguration.class)
public @interface EmbeddedPostgresWithFlyway {
}


FILE: ./src/test/java/dev/vality/disputes/config/EmbeddedPostgresWithFlywayConfiguration.java
MD5:  ea77d12698063a76b71033d4dbf82e51
SHA1: 3e36a349e113194967334cbac0932d8efa12b878
package dev.vality.disputes.config;

import io.zonky.test.db.postgres.embedded.FlywayPreparer;
import io.zonky.test.db.postgres.embedded.PreparedDbProvider;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;

import javax.sql.DataSource;
import java.sql.SQLException;

@TestConfiguration
public class EmbeddedPostgresWithFlywayConfiguration {

    @Bean
    public DataSource dataSource() throws SQLException {
        return PreparedDbProvider
                .forPreparer(FlywayPreparer.forClasspathLocation("db/migration"))
                .createDataSource();
    }
}


FILE: ./src/test/java/dev/vality/disputes/config/EmbeddedPostgresWithFlywaySpringBootITest.java
MD5:  3cfbe535dde7263013016f7d872e460e
SHA1: 702e8e8fe5ce96dc58e07d07f064434636745a81
package dev.vality.disputes.config;

import org.springframework.boot.test.context.SpringBootTest;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target({ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@EmbeddedPostgresWithFlyway
@DisableScheduling
@SpringBootTest
public @interface EmbeddedPostgresWithFlywaySpringBootITest {
}


FILE: ./src/test/java/dev/vality/disputes/config/PostgresqlSpringBootITest.java
MD5:  3484b9071a43e9f08c46b42f644dd91b
SHA1: 08c8be7955e6cec9855ee6c8fc54521e9b2e12b1
package dev.vality.disputes.config;

import dev.vality.testcontainers.annotations.DefaultSpringBootTest;
import dev.vality.testcontainers.annotations.postgresql.PostgresqlTestcontainerSingleton;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target({ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@PostgresqlTestcontainerSingleton
@DisableScheduling
@DefaultSpringBootTest
public @interface PostgresqlSpringBootITest {
}


FILE: ./src/test/java/dev/vality/disputes/config/SpringBootUTest.java
MD5:  5d7c77314a7b9336b094c8d6a9cfb107
SHA1: ea45f9ac6718e03c5b22e4a4e8e0e449c71f5509
package dev.vality.disputes.config;

import dev.vality.testcontainers.annotations.DefaultSpringBootTest;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target({ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@DisableScheduling
@DisableFlyway
@DefaultSpringBootTest
public @interface SpringBootUTest {
}


FILE: ./src/test/java/dev/vality/disputes/config/WireMockSpringBootITest.java
MD5:  e045bdfe76646bf6ff396f6aacbddf7f
SHA1: c9dabeb36e0e6a4d2699543f44fcfc2a358fdbcf
package dev.vality.disputes.config;

import dev.vality.disputes.DisputesApiApplication;
import dev.vality.testcontainers.annotations.postgresql.PostgresqlTestcontainerSingleton;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.wiremock.spring.EnableWireMock;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target({ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@DisableScheduling
@PostgresqlTestcontainerSingleton
@AutoConfigureMockMvc
@Import(WiremockAddressesHolder.class)
@EnableWireMock
@SpringBootTest(
webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
classes = DisputesApiApplication.class,
properties = {"logging.level.WireMock=WARN"})
public @interface WireMockSpringBootITest {
}


FILE: ./src/test/java/dev/vality/disputes/config/WiremockAddressesHolder.java
MD5:  703cd74fa88077ee8aff5fb2d07ce63f
SHA1: b89d83a79a16997212f8c42ee6e549ea0b3d20a6
package dev.vality.disputes.config;

import dev.vality.disputes.util.TestUrlPaths;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.TestComponent;

@TestComponent
public class WiremockAddressesHolder {

    @Value("${wiremock.server.baseUrl}")
    private String baseUrl;

    public String getDownloadUrl() {
        return String.format(baseUrl + TestUrlPaths.S3_PATH + TestUrlPaths.MOCK_DOWNLOAD);
    }

    public String getUploadUrl() {
        return String.format(baseUrl + TestUrlPaths.S3_PATH + TestUrlPaths.MOCK_UPLOAD);
    }

    public String getNotificationUrl() {
        return String.format(baseUrl + TestUrlPaths.NOTIFICATION_PATH);
    }
}


FILE: ./src/test/java/dev/vality/disputes/config/ZonkyEmbeddedPostgres.java
MD5:  2e5707d58d7c03a8929ccae0d02fcfb6
SHA1: 6b92af2390606f1cd75cd85df8f91d45b1e2f7b0
package dev.vality.disputes.config;

import io.zonky.test.db.AutoConfigureEmbeddedDatabase;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target({ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@AutoConfigureEmbeddedDatabase(provider = AutoConfigureEmbeddedDatabase.DatabaseProvider.ZONKY)
public @interface ZonkyEmbeddedPostgres {
}


FILE: ./src/test/java/dev/vality/disputes/config/ZonkyEmbeddedPostgresSpringBootITest.java
MD5:  8248049f41b2828441a50f637808745f
SHA1: 168de8d623e54aaa54377be7255fe3d166ba7655
package dev.vality.disputes.config;

import org.springframework.boot.test.context.SpringBootTest;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target({ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@ZonkyEmbeddedPostgres
@DisableScheduling
@SpringBootTest
public @interface ZonkyEmbeddedPostgresSpringBootITest {
}


FILE: ./src/test/java/dev/vality/disputes/dao/DisputeDaoTest.java
MD5:  069899c64f5c2cd19bf28fcaa13f1596
SHA1: accb00ab683088f6ecfc98615a40781abd2136fa
package dev.vality.disputes.dao;

import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.exception.NotFoundException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.UUID;

import static dev.vality.testcontainers.annotations.util.RandomBeans.random;
import static org.junit.jupiter.api.Assertions.*;

public abstract class DisputeDaoTest {

    @Autowired
    private DisputeDao disputeDao;

    @Test
    public void testInsertAndFind() {
        var random = random(Dispute.class);
        random.setStatus(DisputeStatus.failed);
        disputeDao.save(random);
        assertEquals(random, disputeDao.get(random.getId()));
    }

    @Test
    public void testNotFoundException() {
        assertThrows(NotFoundException.class, () -> disputeDao.get(UUID.randomUUID()));
    }

    @Test
    public void testMultiInsertAndFindLast() {
        var random = random(Dispute.class);
        random.setId(null);
        random.setInvoiceId("setInvoiceId");
        random.setPaymentId("setPaymentId");
        random.setStatus(DisputeStatus.failed);
        disputeDao.save(random);
        disputeDao.save(random);
        disputeDao.save(random);
        assertNotNull(disputeDao.getByInvoiceId(random.getInvoiceId(), random.getPaymentId()));
    }

    @Test
    public void testNextCheckAfter() {
        var random = random(Dispute.class);
        random.setStatus(DisputeStatus.already_exist_created);
        var createdAt = LocalDateTime.now(ZoneOffset.UTC);
        random.setCreatedAt(createdAt);
        random.setPollingBefore(createdAt.plusSeconds(10));
        random.setNextCheckAfter(createdAt.plusSeconds(5));
        disputeDao.save(random);
        assertTrue(disputeDao.getSkipLocked(10, random.getStatus()).isEmpty());
        disputeDao.setNextStepToPending(random.getId(), createdAt.plusSeconds(0));
        assertFalse(disputeDao.getSkipLocked(10, DisputeStatus.pending).isEmpty());
        disputeDao.finishFailed(random.getId(), null);
    }

    @Test
    public void testForgottenNextCheckAfter() {
        var random = random(Dispute.class);
        random.setStatus(DisputeStatus.already_exist_created);
        var createdAt = LocalDateTime.now(ZoneOffset.UTC);
        random.setCreatedAt(createdAt);
        random.setPollingBefore(createdAt.plusSeconds(10));
        random.setNextCheckAfter(createdAt.plusSeconds(5));
        disputeDao.save(random);
        assertTrue(disputeDao.getForgottenSkipLocked(10).isEmpty());
        disputeDao.updateNextPollingInterval(random, createdAt.plusSeconds(0));
        assertFalse(disputeDao.getForgottenSkipLocked(10).isEmpty());
        disputeDao.setNextStepToPending(random.getId(), createdAt.plusSeconds(0));
        assertTrue(disputeDao.getForgottenSkipLocked(10).isEmpty());
        disputeDao.finishFailed(random.getId(), null);
    }
}


FILE: ./src/test/java/dev/vality/disputes/dao/FileMetaDaoTest.java
MD5:  9d3393b8234e67199c968cf98f20c8f5
SHA1: 24912ae0dfd78c408193920dadd257d4e15d01d8
package dev.vality.disputes.dao;

import dev.vality.disputes.config.PostgresqlSpringBootITest;
import dev.vality.disputes.domain.tables.pojos.FileMeta;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.UUID;

import static dev.vality.testcontainers.annotations.util.RandomBeans.random;
import static dev.vality.testcontainers.annotations.util.ValuesGenerator.generateId;
import static org.junit.jupiter.api.Assertions.assertEquals;

@PostgresqlSpringBootITest
public class FileMetaDaoTest {

    @Autowired
    private FileMetaDao fileMetaDao;

    @Test
    public void testInsertAndFind() {
        var disputeId = UUID.fromString("bfdf1dfc-cf66-4d8d-bc34-4d987b3f7351");
        var random = random(FileMeta.class);
        random.setFileId(generateId());
        random.setDisputeId(disputeId);
        fileMetaDao.save(random);
        random.setFileId(generateId());
        fileMetaDao.save(random);
        assertEquals(2, fileMetaDao.getDisputeFiles(disputeId).size());
    }
}


FILE: ./src/test/java/dev/vality/disputes/dao/NotificationDaoTest.java
MD5:  f73d65a99670059fd7c9d74d87b242bb
SHA1: fc305ff46bd941ef9772540cf30478d43ea46263
package dev.vality.disputes.dao;

import dev.vality.disputes.config.PostgresqlSpringBootITest;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.domain.enums.NotificationStatus;
import dev.vality.disputes.domain.tables.pojos.Dispute;
import dev.vality.disputes.domain.tables.pojos.Notification;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.UUID;

import static dev.vality.testcontainers.annotations.util.RandomBeans.random;
import static org.junit.jupiter.api.Assertions.assertEquals;

@PostgresqlSpringBootITest
@SuppressWarnings({"LineLength"})
public class NotificationDaoTest {

    @Autowired
    private NotificationDao notificationDao;
    @Autowired
    private DisputeDao disputeDao;

    @Test
    public void testInsertAndFind() {
        var random = random(Notification.class);
        notificationDao.save(random);
        assertEquals(random, notificationDao.get(random.getDisputeId()));
    }

    @Test
    public void testMultiInsertAndFindActual() {
        var createdAt = LocalDateTime.now(ZoneOffset.UTC);
        // only this is valid
        notificationDao.save(getNotification(NotificationStatus.pending, createdAt, getDispute().getId()));
        notificationDao.save(getNotification(NotificationStatus.delivered, createdAt, getDispute().getId()));
        notificationDao.save(getNotification(NotificationStatus.attempts_limit, createdAt, getDispute().getId()));
        notificationDao.save(getNotification(NotificationStatus.pending, createdAt.plusSeconds(10), getDispute().getId()));
        notificationDao.save(getNotification(NotificationStatus.pending, createdAt, UUID.randomUUID()));
        notificationDao.save(getNotification(NotificationStatus.pending, createdAt, UUID.randomUUID()));
        var notifyRequests = notificationDao.getNotifyRequests(10);
        assertEquals(1, notifyRequests.size());
    }

    @Test
    public void testDelivered() {
        var createdAt = LocalDateTime.now(ZoneOffset.UTC);
        var notification = getNotification(NotificationStatus.pending, createdAt, getDispute().getId());
        notificationDao.save(notification);
        notificationDao.delivered(notification);
        assertEquals(NotificationStatus.delivered, notificationDao.get(notification.getDisputeId()).getStatus());
    }

    @Test
    public void testAttemptsLimit() {
        var createdAt = LocalDateTime.now(ZoneOffset.UTC);
        var notification = getNotification(NotificationStatus.pending, createdAt, getDispute().getId());
        notification.setMaxAttempts(2);
        notificationDao.save(notification);
        notificationDao.updateNextAttempt(notification, createdAt);
        notification = notificationDao.get(notification.getDisputeId());
        assertEquals(1, notification.getMaxAttempts());
        notificationDao.updateNextAttempt(notification, createdAt);
        notification = notificationDao.get(notification.getDisputeId());
        assertEquals(0, notification.getMaxAttempts());
        assertEquals(NotificationStatus.attempts_limit, notification.getStatus());
    }

    private Dispute getDispute() {
        var dispute = random(Dispute.class);
        dispute.setStatus(DisputeStatus.failed);
        disputeDao.save(dispute);
        return dispute;
    }

    private Notification getNotification(NotificationStatus status, LocalDateTime nextAttemptAfter, UUID disputeId) {
        var random = random(Notification.class);
        random.setStatus(status);
        random.setNextAttemptAfter(nextAttemptAfter);
        random.setDisputeId(disputeId);
        random.setMaxAttempts(5);
        return random;
    }
}


FILE: ./src/test/java/dev/vality/disputes/dao/ProviderDisputeDaoTest.java
MD5:  3152d149de7de73eff577a0fa7bc964e
SHA1: 7ced08dbe0018f7cf90d2427419fbd201cc071cb
package dev.vality.disputes.dao;

import dev.vality.disputes.config.PostgresqlSpringBootITest;
import dev.vality.disputes.domain.tables.pojos.ProviderDispute;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import static dev.vality.testcontainers.annotations.util.RandomBeans.random;
import static org.junit.jupiter.api.Assertions.assertEquals;

@PostgresqlSpringBootITest
public class ProviderDisputeDaoTest {

    @Autowired
    private ProviderDisputeDao providerDisputeDao;

    @Test
    public void testInsertAndFind() {
        var random = random(ProviderDispute.class);
        providerDisputeDao.save(random);
        assertEquals(random, providerDisputeDao.get(random.getDisputeId()));
    }
}


FILE: ./src/test/java/dev/vality/disputes/dao/startup/WithEmbeddedPostgresWithFlywayDisputeDaoTest.java
MD5:  4ffa45ccacebc0c9af778909928b2e5d
SHA1: a374690d50fa04666ec1a29370667fce0dd3162e
package dev.vality.disputes.dao.startup;

import dev.vality.disputes.config.EmbeddedPostgresWithFlywaySpringBootITest;
import dev.vality.disputes.dao.DisputeDaoTest;
import org.junit.jupiter.api.Disabled;

@Disabled
@EmbeddedPostgresWithFlywaySpringBootITest
public class WithEmbeddedPostgresWithFlywayDisputeDaoTest extends DisputeDaoTest {
}


FILE: ./src/test/java/dev/vality/disputes/dao/startup/WithTestcontainerDisputeDaoTest.java
MD5:  8af0981569a38c270d86330d344d1500
SHA1: 5e973f5226f586e124548fc8dc0437ee339af216
package dev.vality.disputes.dao.startup;

import dev.vality.disputes.config.PostgresqlSpringBootITest;
import dev.vality.disputes.dao.DisputeDaoTest;

@PostgresqlSpringBootITest
public class WithTestcontainerDisputeDaoTest extends DisputeDaoTest {
}


FILE: ./src/test/java/dev/vality/disputes/dao/startup/WithZonkyEmbeddedPostgresDisputeDaoTest.java
MD5:  0f48e13cb2fa5ac4bb146afc1cdfd29f
SHA1: f339be91a9e0ba18c8af2b29d47c21b421cffa9f
package dev.vality.disputes.dao.startup;

import dev.vality.disputes.config.ZonkyEmbeddedPostgresSpringBootITest;
import dev.vality.disputes.dao.DisputeDaoTest;
import org.junit.jupiter.api.Disabled;

@Disabled
@ZonkyEmbeddedPostgresSpringBootITest
public class WithZonkyEmbeddedPostgresDisputeDaoTest extends DisputeDaoTest {
}


FILE: ./src/test/java/dev/vality/disputes/provider/payments/ProviderCallbackHandlerTest.java
MD5:  616164746cb636849a9d1f320aa7c3f2
SHA1: 8321ce7b4ec623ef757bed137b8cbf935f4c4463
package dev.vality.disputes.provider.payments;

import dev.vality.disputes.config.AbstractMockitoConfig;
import dev.vality.disputes.config.WireMockSpringBootITest;
import dev.vality.disputes.domain.enums.ProviderPaymentsStatus;
import dev.vality.disputes.util.TestUrlPaths;
import dev.vality.provider.payments.ProviderPaymentsCallbackParams;
import dev.vality.provider.payments.ProviderPaymentsCallbackServiceSrv;
import dev.vality.provider.payments.ProviderPaymentsServiceSrv;
import dev.vality.woody.thrift.impl.http.THSpawnClientBuilder;
import lombok.SneakyThrows;
import org.apache.thrift.TException;
import org.junit.jupiter.api.Test;
import org.springframework.test.context.TestPropertySource;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import static dev.vality.disputes.config.NetworkConfig.CALLBACK;
import static dev.vality.disputes.util.MockUtil.*;
import static org.awaitility.Awaitility.await;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.*;

@WireMockSpringBootITest
@TestPropertySource(properties = {
"server.port=${local.server.port}",
"provider.payments.isProviderCallbackEnabled=true",
})
@SuppressWarnings({"LineLength"})
public class ProviderCallbackHandlerTest extends AbstractMockitoConfig {

    @Test
    @SneakyThrows
    public void testSuccess() {
        when(dominantService.getTerminal(any())).thenReturn(createTerminal().get());
        when(dominantService.getCurrency(any())).thenReturn(createCurrency().get());
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy(String.format("http://127.0.0.1:%s%s", 8023, TestUrlPaths.ADAPTER)).get());
        var providerMock = mock(ProviderPaymentsServiceSrv.Client.class);
        when(providerMock.checkPaymentStatus(any(), any())).thenReturn(createPaymentStatusResult());
        when(providerPaymentsThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        var minNumberOfInvocations = 4;
        for (int i = 0; i < minNumberOfInvocations; i++) {
            var invoiceId = String.valueOf(i);
            var paymentId = String.valueOf(i);
            executeCallbackIFace(invoiceId, paymentId);
        }
        await().atMost(30, TimeUnit.SECONDS)
                .untilAsserted(() -> verify(providerCallbackDao, atLeast(minNumberOfInvocations)).save(any()));
        var providerCallbackIds = new ArrayList<UUID>();
        for (var providerCallback : providerPaymentsService.getPaymentsForHgCall(Integer.MAX_VALUE)) {
            providerCallbackIds.add(providerCallback.getId());
            var reason = providerPaymentsAdjustmentExtractor.getReason(providerCallback);
            var invoicePayment = createInvoicePayment(providerCallback.getPaymentId());
            invoicePayment.setAdjustments(List.of(getCashFlowInvoicePaymentAdjustment("adjustmentId", reason)));
            when(invoicingClient.getPayment(any(), any())).thenReturn(invoicePayment);
            when(invoicingClient.createPaymentAdjustment(any(), any(), any()))
                    .thenReturn(getCapturedInvoicePaymentAdjustment("adjustmentId", reason));
            providerPaymentsService.callHgForCreateAdjustment(providerCallback);
        }
        for (var providerCallbackId : providerCallbackIds) {
            var providerCallback = providerCallbackDao.getProviderCallbackForUpdateSkipLocked(providerCallbackId);
            assertEquals(ProviderPaymentsStatus.succeeded, providerCallback.getStatus());
        }
    }

    private void executeCallbackIFace(String invoiceId, String paymentId) throws TException, URISyntaxException {
        var invoice = createInvoice(invoiceId, paymentId);
        when(invoicingClient.getPayment(any(), any())).thenReturn(invoice.getPayments().getFirst());
        var request = new ProviderPaymentsCallbackParams()
                .setInvoiceId(invoiceId)
                .setPaymentId(paymentId);
        createProviderPaymentsCallbackIface().createAdjustmentWhenFailedPaymentSuccess(request);
    }

    private ProviderPaymentsCallbackServiceSrv.Iface createProviderPaymentsCallbackIface() throws URISyntaxException {
        return new THSpawnClientBuilder()
                .withAddress(new URI("http://127.0.0.1:" + serverPort + CALLBACK))
                .withNetworkTimeout(5000)
                .build(ProviderPaymentsCallbackServiceSrv.Iface.class);
    }
}


FILE: ./src/test/java/dev/vality/disputes/provider/payments/ProviderPaymentsServiceTest.java
MD5:  eb117a01531a3fdb6b1509f4b15625cc
SHA1: 3dc607ce58b81f9b3a6bfe43c2f01f24eb1bd196
package dev.vality.disputes.provider.payments;

import dev.vality.damsel.domain.InvoicePaymentCaptured;
import dev.vality.damsel.domain.InvoicePaymentRefunded;
import dev.vality.damsel.domain.InvoicePaymentStatus;
import dev.vality.disputes.config.AbstractMockitoConfig;
import dev.vality.disputes.config.WireMockSpringBootITest;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.domain.enums.ProviderPaymentsStatus;
import lombok.SneakyThrows;
import org.junit.jupiter.api.Test;
import org.springframework.test.context.TestPropertySource;

import static dev.vality.disputes.util.MockUtil.createInvoicePayment;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@WireMockSpringBootITest
@TestPropertySource(properties = {
"server.port=${local.server.port}",
"provider.payments.isProviderCallbackEnabled=true",
})
@SuppressWarnings({"VariableDeclarationUsageDistance", "LineLength"})
public class ProviderPaymentsServiceTest extends AbstractMockitoConfig {

    @Test
    @SneakyThrows
    public void testProviderPaymentsSuccessResult() {
        var disputeId = providerCallbackFlowHandler.handleSuccess();
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testFailedWhenInvoicePaymentStatusIsRefunded() {
        var disputeId = pendingFlowHandler.handlePending();
        var dispute = disputeDao.get(disputeId);
        var providerCallback = providerCallbackDao.get(dispute.getInvoiceId(), dispute.getPaymentId());
        var invoicePayment = createInvoicePayment(providerCallback.getPaymentId());
        invoicePayment.getPayment().setStatus(InvoicePaymentStatus.refunded(new InvoicePaymentRefunded()));
        when(invoicingClient.getPayment(any(), any())).thenReturn(invoicePayment);
        providerPaymentsService.callHgForCreateAdjustment(providerCallback);
        providerCallback = providerCallbackDao.get(dispute.getInvoiceId(), dispute.getPaymentId());
        assertEquals(ProviderPaymentsStatus.failed, providerCallback.getStatus());
        assertEquals(DisputeStatus.failed, disputeDao.get(disputeId).getStatus());
    }

    @Test
    @SneakyThrows
    public void testSuccessWhenInvoicePaymentStatusIsCaptured() {
        var disputeId = pendingFlowHandler.handlePending();
        var dispute = disputeDao.get(disputeId);
        var providerCallback = providerCallbackDao.get(dispute.getInvoiceId(), dispute.getPaymentId());
        var invoicePayment = createInvoicePayment(providerCallback.getPaymentId());
        invoicePayment.getPayment().setStatus(InvoicePaymentStatus.captured(new InvoicePaymentCaptured()));
        when(invoicingClient.getPayment(any(), any())).thenReturn(invoicePayment);
        providerPaymentsService.callHgForCreateAdjustment(providerCallback);
        providerCallback = providerCallbackDao.get(dispute.getInvoiceId(), dispute.getPaymentId());
        assertEquals(ProviderPaymentsStatus.succeeded, providerCallback.getStatus());
        assertEquals(DisputeStatus.succeeded, disputeDao.get(disputeId).getStatus());
    }
}


FILE: ./src/test/java/dev/vality/disputes/schedule/service/CreatedDisputesServiceTest.java
MD5:  ceb1448908865c2b3cbb89b4d3a4b968
SHA1: 3ece7baac00389a0c212a65f25bd1443cf2d6c91
package dev.vality.disputes.schedule.service;

import dev.vality.damsel.domain.InvoicePaymentCaptured;
import dev.vality.damsel.domain.InvoicePaymentRefunded;
import dev.vality.damsel.domain.InvoicePaymentStatus;
import dev.vality.disputes.config.AbstractMockitoConfig;
import dev.vality.disputes.config.WireMockSpringBootITest;
import dev.vality.disputes.constant.ErrorMessage;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.domain.enums.ProviderPaymentsStatus;
import dev.vality.disputes.provider.ProviderDisputesServiceSrv;
import dev.vality.disputes.util.MockUtil;
import dev.vality.disputes.util.TestUrlPaths;
import lombok.SneakyThrows;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.web.server.LocalServerPort;

import java.util.UUID;

import static dev.vality.disputes.constant.ModerationPrefix.DISPUTES_UNKNOWN_MAPPING;
import static dev.vality.disputes.util.MockUtil.*;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@WireMockSpringBootITest
@SuppressWarnings({"LineLength", "VariableDeclarationUsageDistance"})
public class CreatedDisputesServiceTest extends AbstractMockitoConfig {

    @LocalServerPort
    private int serverPort;

    @Test
    public void testDisputeCreatedSuccessResult() {
        var disputeId = createdFlowHandler.handleCreate();
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testPaymentNotFound() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.failed, disputeDao.get(disputeId).getStatus());
        assertEquals(ErrorMessage.PAYMENT_NOT_FOUND, disputeDao.get(disputeId).getErrorMessage());
    }

    @Test
    @SneakyThrows
    public void testNoAttachments() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        when(invoicingClient.getPayment(any(), any())).thenReturn(MockUtil.createInvoicePayment(paymentId));
        when(dominantService.getTerminal(any())).thenReturn(createTerminal().get());
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy().get());
        createdFlowHandler.mockFailStatusProviderPayment();
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.failed, disputeDao.get(disputeId).getStatus());
        assertEquals(ErrorMessage.NO_ATTACHMENTS, disputeDao.get(disputeId).getErrorMessage());
    }

    @Test
    @SneakyThrows
    public void testManualPendingWhenIsNotProviderDisputesApiExist() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        when(invoicingClient.getPayment(any(), any())).thenReturn(MockUtil.createInvoicePayment(paymentId));
        when(fileStorageClient.generateDownloadUrl(any(), any())).thenReturn(wiremockAddressesHolder.getDownloadUrl());
        when(dominantService.getTerminal(any())).thenReturn(createTerminal().get());
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy().get());
        createdFlowHandler.mockFailStatusProviderPayment();
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.manual_pending, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testDisputeCreatedFailResult() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        when(invoicingClient.getPayment(any(), any())).thenReturn(MockUtil.createInvoicePayment(paymentId));
        when(fileStorageClient.generateDownloadUrl(any(), any())).thenReturn(wiremockAddressesHolder.getDownloadUrl());
        var terminal = createTerminal().get();
        terminal.getOptions().putAll(getOptions());
        when(dominantService.getTerminal(any())).thenReturn(terminal);
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy().get());
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        when(providerMock.createDispute(any())).thenReturn(createDisputeCreatedFailResult());
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        createdFlowHandler.mockFailStatusProviderPayment();
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.failed, disputeDao.get(disputeId).getStatus());
    }

    @Test
    @SneakyThrows
    public void testManualPendingWhenDisputeCreatedFailResultWithDisputesUnknownMapping() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        when(invoicingClient.getPayment(any(), any())).thenReturn(MockUtil.createInvoicePayment(paymentId));
        when(fileStorageClient.generateDownloadUrl(any(), any())).thenReturn(wiremockAddressesHolder.getDownloadUrl());
        var terminal = createTerminal().get();
        terminal.getOptions().putAll(getOptions());
        when(dominantService.getTerminal(any())).thenReturn(terminal);
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy().get());
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        var disputeCreatedFailResult = createDisputeCreatedFailResult();
        disputeCreatedFailResult.getFailResult().getFailure().setCode(DISPUTES_UNKNOWN_MAPPING);
        when(providerMock.createDispute(any())).thenReturn(disputeCreatedFailResult);
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        createdFlowHandler.mockFailStatusProviderPayment();
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.manual_pending, disputeDao.get(disputeId).getStatus());
        assertTrue(disputeDao.get(disputeId).getErrorMessage().contains(DISPUTES_UNKNOWN_MAPPING));
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testManualPendingWhenUnexpectedResultMapping() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        when(invoicingClient.getPayment(any(), any())).thenReturn(MockUtil.createInvoicePayment(paymentId));
        when(fileStorageClient.generateDownloadUrl(any(), any())).thenReturn(wiremockAddressesHolder.getDownloadUrl());
        var terminal = createTerminal().get();
        terminal.getOptions().putAll(getOptions());
        when(dominantService.getTerminal(any())).thenReturn(terminal);
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        // routeUrl = "http://127.0.0.1:8023/disputes" == exist api
        when(dominantService.getProxy(any())).thenReturn(createProxyWithRealAddress(serverPort).get());
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        when(providerMock.createDispute(any())).thenThrow(getUnexpectedResultWException());
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        createdFlowHandler.mockFailStatusProviderPayment();
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.manual_pending, disputeDao.get(disputeId).getStatus());
        assertTrue(disputeDao.get(disputeId).getErrorMessage().contains("Unexpected result"));
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testManualPendingWhenUnexpectedResult() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        when(invoicingClient.getPayment(any(), any())).thenReturn(MockUtil.createInvoicePayment(paymentId));
        when(fileStorageClient.generateDownloadUrl(any(), any())).thenReturn(wiremockAddressesHolder.getDownloadUrl());
        var terminal = createTerminal().get();
        terminal.getOptions().putAll(getOptions());
        when(dominantService.getTerminal(any())).thenReturn(terminal);
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxyNotFoundCase(serverPort).get());
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        when(providerMock.createDispute(any())).thenThrow(getUnexpectedResultWException());
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        createdFlowHandler.mockFailStatusProviderPayment();
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.manual_pending, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testDisputeCreatedAlreadyExistResult() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        when(invoicingClient.getPayment(any(), any())).thenReturn(MockUtil.createInvoicePayment(paymentId));
        when(fileStorageClient.generateDownloadUrl(any(), any())).thenReturn(wiremockAddressesHolder.getDownloadUrl());
        var terminal = createTerminal().get();
        terminal.getOptions().putAll(getOptions());
        when(dominantService.getTerminal(any())).thenReturn(terminal);
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy().get());
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        when(providerMock.createDispute(any())).thenReturn(createDisputeAlreadyExistResult());
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        createdFlowHandler.mockFailStatusProviderPayment();
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.already_exist_created, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testFailedWhenInvoicePaymentStatusIsRefunded() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        var invoicePayment = createInvoicePayment(paymentId);
        invoicePayment.getPayment().setStatus(InvoicePaymentStatus.refunded(new InvoicePaymentRefunded()));
        when(invoicingClient.getPayment(any(), any())).thenReturn(invoicePayment);
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.failed, disputeDao.get(disputeId).getStatus());
    }

    @Test
    @SneakyThrows
    public void testSuccessWhenInvoicePaymentStatusIsCaptured() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        var invoicePayment = createInvoicePayment(paymentId);
        invoicePayment.getPayment().setStatus(InvoicePaymentStatus.captured(new InvoicePaymentCaptured()));
        when(invoicingClient.getPayment(any(), any())).thenReturn(invoicePayment);
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.succeeded, disputeDao.get(disputeId).getStatus());
    }

    @Test
    @SneakyThrows
    public void createAdjustmentWhenSuccessStatusProviderPayment() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        when(invoicingClient.getPayment(any(), any())).thenReturn(MockUtil.createInvoicePayment(paymentId));
        when(fileStorageClient.generateDownloadUrl(any(), any())).thenReturn(wiremockAddressesHolder.getDownloadUrl());
        var terminal = createTerminal().get();
        terminal.getOptions().putAll(getOptions());
        when(dominantService.getTerminal(any())).thenReturn(terminal);
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy(String.format("http://127.0.0.1:%s%s", 8023, TestUrlPaths.ADAPTER)).get());
        createdFlowHandler.mockSuccessStatusProviderPayment();
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.create_adjustment, disputeDao.get(disputeId).getStatus());
        assertEquals(ProviderPaymentsStatus.create_adjustment, providerCallbackDao.get(dispute.getInvoiceId(), dispute.getPaymentId()).getStatus());
    }
}


FILE: ./src/test/java/dev/vality/disputes/schedule/service/ForgottenDisputesServiceTest.java
MD5:  d57487eb28c68445e58c80c0e5b154b2
SHA1: 0be57dadbb17755ba7fd55a9fe6fe3b3e3b61355
package dev.vality.disputes.schedule.service;

import dev.vality.damsel.domain.InvoicePaymentCaptured;
import dev.vality.damsel.domain.InvoicePaymentRefunded;
import dev.vality.damsel.domain.InvoicePaymentStatus;
import dev.vality.disputes.config.AbstractMockitoConfig;
import dev.vality.disputes.config.WireMockSpringBootITest;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.schedule.core.ForgottenDisputesService;
import lombok.SneakyThrows;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import static dev.vality.disputes.util.MockUtil.createInvoicePayment;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@WireMockSpringBootITest
public class ForgottenDisputesServiceTest extends AbstractMockitoConfig {

    @Autowired
    private ForgottenDisputesService forgottenDisputesService;

    @Test
    @SneakyThrows
    public void testUpdateNextPollingInterval() {
        var disputeId = createdFlowHandler.handleCreate();
        var dispute = disputeDao.get(disputeId);
        when(invoicingClient.getPayment(any(), any())).thenReturn(createInvoicePayment(dispute.getPaymentId()));
        forgottenDisputesService.process(dispute);
        assertNotEquals(dispute.getNextCheckAfter(), disputeDao.get(disputeId).getNextCheckAfter());
    }

    @Test
    @SneakyThrows
    public void testFailedWhenInvoicePaymentStatusIsRefunded() {
        var disputeId = createdFlowHandler.handleCreate();
        var dispute = disputeDao.get(disputeId);
        var invoicePayment = createInvoicePayment(dispute.getPaymentId());
        invoicePayment.getPayment().setStatus(InvoicePaymentStatus.refunded(new InvoicePaymentRefunded()));
        when(invoicingClient.getPayment(any(), any())).thenReturn(invoicePayment);
        forgottenDisputesService.process(dispute);
        assertEquals(DisputeStatus.failed, disputeDao.get(disputeId).getStatus());
    }

    @Test
    @SneakyThrows
    public void testSuccessWhenInvoicePaymentStatusIsCaptured() {
        var disputeId = createdFlowHandler.handleCreate();
        var dispute = disputeDao.get(disputeId);
        var invoicePayment = createInvoicePayment(dispute.getPaymentId());
        invoicePayment.getPayment().setStatus(InvoicePaymentStatus.captured(new InvoicePaymentCaptured()));
        when(invoicingClient.getPayment(any(), any())).thenReturn(invoicePayment);
        forgottenDisputesService.process(dispute);
        assertEquals(DisputeStatus.succeeded, disputeDao.get(disputeId).getStatus());
    }
}


FILE: ./src/test/java/dev/vality/disputes/schedule/service/NotificationServiceTest.java
MD5:  91cdb4266398bab14bfc45d600bda79d
SHA1: 29067e3d718f415f6b410bbe61ac1c10f26e715d
package dev.vality.disputes.schedule.service;

import dev.vality.disputes.config.AbstractMockitoConfig;
import dev.vality.disputes.config.WireMockSpringBootITest;
import dev.vality.disputes.dao.NotificationDao;
import dev.vality.disputes.domain.enums.NotificationStatus;
import dev.vality.disputes.schedule.core.NotificationService;
import dev.vality.disputes.util.WiremockUtils;
import lombok.SneakyThrows;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

@WireMockSpringBootITest
@SuppressWarnings({"LineLength"})
public class NotificationServiceTest extends AbstractMockitoConfig {

    @Autowired
    private NotificationDao notificationDao;
    @Autowired
    private NotificationService notificationService;

    @Test
    @SneakyThrows
    public void testNotificationDelivered() {
        var disputeId = providerCallbackFlowHandler.handleSuccess();
        WiremockUtils.mockNotificationSuccess();
        var notifyRequest = notificationDao.getNotifyRequest(disputeId);
        notificationService.process(notifyRequest);
        Assertions.assertEquals(NotificationStatus.delivered, notificationDao.get(disputeId).getStatus());
    }

    @Test
    @SneakyThrows
    public void testNotificationDeliveredAfterMerchantInternalErrors() {
        var disputeId = providerCallbackFlowHandler.handleSuccess();
        WiremockUtils.mockNotification500();
        var notifyRequest = notificationDao.getNotifyRequest(disputeId);
        notificationService.process(notifyRequest);
        Assertions.assertEquals(NotificationStatus.pending, notificationDao.get(disputeId).getStatus());
        Assertions.assertEquals(4, notificationDao.get(disputeId).getMaxAttempts());
        notificationService.process(notifyRequest);
        Assertions.assertEquals(NotificationStatus.pending, notificationDao.get(disputeId).getStatus());
        Assertions.assertEquals(3, notificationDao.get(disputeId).getMaxAttempts());
        WiremockUtils.mockNotificationSuccess();
        notificationService.process(notifyRequest);
        Assertions.assertEquals(NotificationStatus.delivered, notificationDao.get(disputeId).getStatus());
    }
}


FILE: ./src/test/java/dev/vality/disputes/schedule/service/PendingDisputesServiceTest.java
MD5:  2ddd1dcecb9cd99ad057631ad6c90988
SHA1: b5535b0a80b30aeac25cc43e736d1f6491a84727
package dev.vality.disputes.schedule.service;

import dev.vality.damsel.domain.InvoicePaymentCaptured;
import dev.vality.damsel.domain.InvoicePaymentRefunded;
import dev.vality.damsel.domain.InvoicePaymentStatus;
import dev.vality.disputes.config.AbstractMockitoConfig;
import dev.vality.disputes.config.WireMockSpringBootITest;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.provider.ProviderDisputesServiceSrv;
import dev.vality.disputes.util.MockUtil;
import lombok.SneakyThrows;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static dev.vality.disputes.constant.ModerationPrefix.DISPUTES_UNKNOWN_MAPPING;
import static dev.vality.disputes.util.MockUtil.*;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@WireMockSpringBootITest
public class PendingDisputesServiceTest extends AbstractMockitoConfig {

    @Test
    public void testDisputeStatusSuccessResult() {
        var disputeId = pendingFlowHandler.handlePending();
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testDisputeStatusPendingResult() {
        var disputeId = createdFlowHandler.handleCreate();
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        when(providerMock.checkDisputeStatus(any())).thenReturn(createDisputeStatusPendingResult());
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        var dispute = disputeDao.get(disputeId);
        pendingDisputesService.callPendingDisputeRemotely(dispute);
        assertEquals(DisputeStatus.pending, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testProviderDisputeNotFound() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        disputeDao.setNextStepToPending(disputeId, null);
        when(invoicingClient.getPayment(any(), any())).thenReturn(MockUtil.createInvoicePayment(paymentId));
        var terminal = createTerminal().get();
        terminal.getOptions().putAll(getOptions());
        when(dominantService.getTerminal(any())).thenReturn(terminal);
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy().get());
        var dispute = disputeDao.get(disputeId);
        pendingDisputesService.callPendingDisputeRemotely(dispute);
        assertEquals(DisputeStatus.created, disputeDao.get(disputeId).getStatus());
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testDisputeStatusFailResult() {
        var disputeId = createdFlowHandler.handleCreate();
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        when(providerMock.checkDisputeStatus(any())).thenReturn(createDisputeStatusFailResult());
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        var dispute = disputeDao.get(disputeId);
        pendingDisputesService.callPendingDisputeRemotely(dispute);
        assertEquals(DisputeStatus.failed, disputeDao.get(disputeId).getStatus());
    }

    @Test
    @SneakyThrows
    public void testManualPendingWhenStatusFailResultWithDisputesUnknownMapping() {
        var disputeId = createdFlowHandler.handleCreate();
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        var disputeStatusFailResult = createDisputeStatusFailResult();
        disputeStatusFailResult.getStatusFail().getFailure().setCode(DISPUTES_UNKNOWN_MAPPING);
        when(providerMock.checkDisputeStatus(any())).thenReturn(disputeStatusFailResult);
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        var dispute = disputeDao.get(disputeId);
        pendingDisputesService.callPendingDisputeRemotely(dispute);
        assertEquals(DisputeStatus.manual_pending, disputeDao.get(disputeId).getStatus());
        assertTrue(disputeDao.get(disputeId).getErrorMessage().contains(DISPUTES_UNKNOWN_MAPPING));
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testManualPendingWhenUnexpectedResultMapping() {
        var disputeId = createdFlowHandler.handleCreate();
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        when(providerMock.checkDisputeStatus(any())).thenThrow(getUnexpectedResultWException());
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        var dispute = disputeDao.get(disputeId);
        pendingDisputesService.callPendingDisputeRemotely(dispute);
        assertEquals(DisputeStatus.manual_pending, disputeDao.get(disputeId).getStatus());
        assertTrue(disputeDao.get(disputeId).getErrorMessage().contains("Unexpected result"));
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testManualPendingWhenUnexpectedResultBase64Mapping() {
        var disputeId = createdFlowHandler.handleCreate();
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        when(providerMock.checkDisputeStatus(any())).thenThrow(getUnexpectedResultBase64WException());
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        var dispute = disputeDao.get(disputeId);
        pendingDisputesService.callPendingDisputeRemotely(dispute);
        assertEquals(DisputeStatus.manual_pending, disputeDao.get(disputeId).getStatus());
        assertTrue(disputeDao.get(disputeId).getErrorMessage().contains("Unexpected result"));
        disputeDao.finishFailed(disputeId, null);
    }

    @Test
    @SneakyThrows
    public void testFailedWhenInvoicePaymentStatusIsRefunded() {
        var disputeId = createdFlowHandler.handleCreate();
        var dispute = disputeDao.get(disputeId);
        var invoicePayment = createInvoicePayment(dispute.getPaymentId());
        invoicePayment.getPayment().setStatus(InvoicePaymentStatus.refunded(new InvoicePaymentRefunded()));
        when(invoicingClient.getPayment(any(), any())).thenReturn(invoicePayment);
        pendingDisputesService.callPendingDisputeRemotely(dispute);
        assertEquals(DisputeStatus.failed, disputeDao.get(disputeId).getStatus());
    }

    @Test
    @SneakyThrows
    public void testSuccessWhenInvoicePaymentStatusIsCaptured() {
        var disputeId = createdFlowHandler.handleCreate();
        var dispute = disputeDao.get(disputeId);
        var invoicePayment = createInvoicePayment(dispute.getPaymentId());
        invoicePayment.getPayment().setStatus(InvoicePaymentStatus.captured(new InvoicePaymentCaptured()));
        when(invoicingClient.getPayment(any(), any())).thenReturn(invoicePayment);
        pendingDisputesService.callPendingDisputeRemotely(dispute);
        assertEquals(DisputeStatus.succeeded, disputeDao.get(disputeId).getStatus());
    }
}


FILE: ./src/test/java/dev/vality/disputes/schedule/service/config/CreatedFlowHandler.java
MD5:  72e4aa0479ddc007e4cd8aefb5d00504
SHA1: 7997d20b4c1255c670f4abd8d99b7cdb2a8f205c
package dev.vality.disputes.schedule.service.config;

import dev.vality.damsel.payment_processing.InvoicingSrv;
import dev.vality.disputes.config.WiremockAddressesHolder;
import dev.vality.disputes.dao.DisputeDao;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.provider.ProviderDisputesServiceSrv;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsThriftInterfaceBuilder;
import dev.vality.disputes.schedule.core.CreatedDisputesService;
import dev.vality.disputes.schedule.service.ProviderDisputesThriftInterfaceBuilder;
import dev.vality.disputes.service.external.DominantService;
import dev.vality.disputes.util.MockUtil;
import dev.vality.disputes.util.TestUrlPaths;
import dev.vality.file.storage.FileStorageSrv;
import dev.vality.provider.payments.PaymentStatusResult;
import dev.vality.provider.payments.ProviderPaymentsServiceSrv;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;

import java.util.UUID;

import static dev.vality.disputes.util.MockUtil.*;
import static dev.vality.testcontainers.annotations.util.ValuesGenerator.generateId;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@RequiredArgsConstructor
@SuppressWarnings({"LineLength", "VariableDeclarationUsageDistance"})
public class CreatedFlowHandler {

    private final InvoicingSrv.Iface invoicingClient;
    private final FileStorageSrv.Iface fileStorageClient;
    private final DisputeDao disputeDao;
    private final DominantService dominantService;
    private final CreatedDisputesService createdDisputesService;
    private final ProviderDisputesThriftInterfaceBuilder providerDisputesThriftInterfaceBuilder;
    private final ProviderPaymentsThriftInterfaceBuilder providerPaymentsThriftInterfaceBuilder;
    private final WiremockAddressesHolder wiremockAddressesHolder;
    private final MerchantApiMvcPerformer merchantApiMvcPerformer;

    @SneakyThrows
    public UUID handleCreate() {
        var invoiceId = "20McecNnWoy";
        var paymentId = "1";
        var providerDisputeId = generateId();
        var disputeId = UUID.fromString(merchantApiMvcPerformer.createDispute(invoiceId, paymentId).getDisputeId());
        when(invoicingClient.getPayment(any(), any())).thenReturn(MockUtil.createInvoicePayment(paymentId));
        when(fileStorageClient.generateDownloadUrl(any(), any())).thenReturn(wiremockAddressesHolder.getDownloadUrl());
        var terminal = createTerminal().get();
        terminal.getOptions().putAll(getOptions());
        when(dominantService.getTerminal(any())).thenReturn(terminal);
        when(dominantService.getProvider(any())).thenReturn(createProvider().get());
        when(dominantService.getProxy(any())).thenReturn(createProxy(String.format("http://127.0.0.1:%s%s", 8023, TestUrlPaths.ADAPTER)).get());
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        when(providerMock.createDispute(any())).thenReturn(createDisputeCreatedSuccessResult(providerDisputeId));
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        mockFailStatusProviderPayment();
        var dispute = disputeDao.get(disputeId);
        createdDisputesService.callCreateDisputeRemotely(dispute);
        assertEquals(DisputeStatus.pending, disputeDao.get(disputeId).getStatus());
        return disputeId;
    }

    @SneakyThrows
    public void mockFailStatusProviderPayment() {
        var providerPaymentMock = mock(ProviderPaymentsServiceSrv.Client.class);
        when(providerPaymentMock.checkPaymentStatus(any(), any())).thenReturn(new PaymentStatusResult(false));
        when(providerPaymentsThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerPaymentMock);
    }

    @SneakyThrows
    public void mockSuccessStatusProviderPayment() {
        var providerPaymentMock = mock(ProviderPaymentsServiceSrv.Client.class);
        when(providerPaymentMock.checkPaymentStatus(any(), any())).thenReturn(new PaymentStatusResult(true).setChangedAmount(Long.MAX_VALUE));
        when(providerPaymentsThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerPaymentMock);
    }
}


FILE: ./src/test/java/dev/vality/disputes/schedule/service/config/MerchantApiMvcPerformer.java
MD5:  ccc5ce017968e52636288b3e72e39ae8
SHA1: a94b5b1a2483780a48d6d5e78b9cbe0248790bee
package dev.vality.disputes.schedule.service.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.vality.bouncer.decisions.ArbiterSrv;
import dev.vality.damsel.payment_processing.InvoicingSrv;
import dev.vality.disputes.config.WiremockAddressesHolder;
import dev.vality.disputes.service.external.PartyManagementService;
import dev.vality.disputes.service.external.impl.dominant.DominantAsyncService;
import dev.vality.disputes.util.MockUtil;
import dev.vality.disputes.util.OpenApiUtil;
import dev.vality.disputes.util.WiremockUtils;
import dev.vality.file.storage.FileStorageSrv;
import dev.vality.swag.disputes.model.Create200Response;
import dev.vality.token.keeper.TokenAuthenticatorSrv;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static dev.vality.disputes.util.MockUtil.*;
import static java.util.UUID.randomUUID;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SuppressWarnings({"LineLength"})
@RequiredArgsConstructor
public class MerchantApiMvcPerformer {

    private final InvoicingSrv.Iface invoicingClient;
    private final TokenAuthenticatorSrv.Iface tokenKeeperClient;
    private final ArbiterSrv.Iface bouncerClient;
    private final FileStorageSrv.Iface fileStorageClient;
    private final DominantAsyncService dominantAsyncService;
    private final PartyManagementService partyManagementService;
    private final WiremockAddressesHolder wiremockAddressesHolder;
    private final MockMvc mvc;

    @SneakyThrows
    public Create200Response createDispute(String invoiceId, String paymentId) {
        when(invoicingClient.get(any(), any())).thenReturn(MockUtil.createInvoice(invoiceId, paymentId));
        when(tokenKeeperClient.authenticate(any(), any())).thenReturn(createAuthData());
        when(bouncerClient.judge(any(), any())).thenReturn(createJudgementAllowed());
        when(dominantAsyncService.getTerminal(any())).thenReturn(createTerminal());
        when(dominantAsyncService.getCurrency(any())).thenReturn(createCurrency());
        when(dominantAsyncService.getProvider(any())).thenReturn(createProvider());
        when(dominantAsyncService.getProxy(any())).thenReturn(createProxy());
        when(partyManagementService.getShop(any(), any())).thenReturn(createShop());
        when(fileStorageClient.createNewFile(any(), any())).thenReturn(createNewFileResult(wiremockAddressesHolder.getUploadUrl()));
        WiremockUtils.mockS3AttachmentUpload();
        var resultActions = mvc.perform(post("/disputes/create")
                        .header("Authorization", "Bearer token")
                        .header("X-Request-ID", randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(OpenApiUtil.getContentCreateRequest(invoiceId, paymentId, wiremockAddressesHolder.getNotificationUrl())))
                .andExpect(status().is2xxSuccessful())
                .andExpect(jsonPath("$.disputeId").isNotEmpty());
        return new ObjectMapper().readValue(resultActions.andReturn().getResponse().getContentAsString(), Create200Response.class);
    }
}


FILE: ./src/test/java/dev/vality/disputes/schedule/service/config/PendingFlowHandler.java
MD5:  6ecd6d970fec33534413c31b935f06b1
SHA1: 9349e62ac8736fde82e0b9774ef340c6b82bad03
package dev.vality.disputes.schedule.service.config;

import dev.vality.disputes.dao.DisputeDao;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.domain.enums.ProviderPaymentsStatus;
import dev.vality.disputes.provider.ProviderDisputesServiceSrv;
import dev.vality.disputes.provider.payments.dao.ProviderCallbackDao;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsThriftInterfaceBuilder;
import dev.vality.disputes.schedule.core.PendingDisputesService;
import dev.vality.disputes.schedule.service.ProviderDisputesThriftInterfaceBuilder;
import dev.vality.provider.payments.PaymentStatusResult;
import dev.vality.provider.payments.ProviderPaymentsServiceSrv;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;

import java.util.UUID;

import static dev.vality.disputes.util.MockUtil.createDisputeStatusSuccessResult;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@SuppressWarnings({"LineLength"})
@RequiredArgsConstructor
public class PendingFlowHandler {

    private final DisputeDao disputeDao;
    private final ProviderCallbackDao providerCallbackDao;
    private final CreatedFlowHandler createdFlowHandler;
    private final PendingDisputesService pendingDisputesService;
    private final ProviderDisputesThriftInterfaceBuilder providerDisputesThriftInterfaceBuilder;
    private final ProviderPaymentsThriftInterfaceBuilder providerPaymentsThriftInterfaceBuilder;

    @SneakyThrows
    public UUID handlePending() {
        var disputeId = createdFlowHandler.handleCreate();
        var providerMock = mock(ProviderDisputesServiceSrv.Client.class);
        when(providerMock.checkDisputeStatus(any())).thenReturn(createDisputeStatusSuccessResult());
        when(providerDisputesThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerMock);
        var providerPaymentMock = mock(ProviderPaymentsServiceSrv.Client.class);
        when(providerPaymentMock.checkPaymentStatus(any(), any())).thenReturn(new PaymentStatusResult(true));
        when(providerPaymentsThriftInterfaceBuilder.buildWoodyClient(any())).thenReturn(providerPaymentMock);
        var dispute = disputeDao.get(disputeId);
        pendingDisputesService.callPendingDisputeRemotely(dispute);
        assertEquals(DisputeStatus.create_adjustment, disputeDao.get(disputeId).getStatus());
        assertEquals(ProviderPaymentsStatus.create_adjustment, providerCallbackDao.get(dispute.getInvoiceId(), dispute.getPaymentId()).getStatus());
        return disputeId;
    }
}


FILE: ./src/test/java/dev/vality/disputes/schedule/service/config/ProviderCallbackFlowHandler.java
MD5:  bba102c834b003205d1f7c305021bde3
SHA1: 1ee14dab1be2b735f154202caccef30ea9aeeb6f
package dev.vality.disputes.schedule.service.config;

import dev.vality.damsel.payment_processing.InvoicingSrv;
import dev.vality.disputes.dao.DisputeDao;
import dev.vality.disputes.domain.enums.DisputeStatus;
import dev.vality.disputes.domain.enums.ProviderPaymentsStatus;
import dev.vality.disputes.provider.payments.dao.ProviderCallbackDao;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsAdjustmentExtractor;
import dev.vality.disputes.provider.payments.service.ProviderPaymentsService;
import lombok.RequiredArgsConstructor;
import lombok.SneakyThrows;

import java.util.List;
import java.util.UUID;

import static dev.vality.disputes.util.MockUtil.*;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@RequiredArgsConstructor
@SuppressWarnings({"LineLength", "VariableDeclarationUsageDistance"})
public class ProviderCallbackFlowHandler {

    private final InvoicingSrv.Iface invoicingClient;
    private final DisputeDao disputeDao;
    private final ProviderCallbackDao providerCallbackDao;
    private final PendingFlowHandler pendingFlowHandler;
    private final ProviderPaymentsService providerPaymentsService;
    private final ProviderPaymentsAdjustmentExtractor providerPaymentsAdjustmentExtractor;

    @SneakyThrows
    public UUID handleSuccess() {
        var disputeId = pendingFlowHandler.handlePending();
        var dispute = disputeDao.get(disputeId);
        var providerCallback = providerCallbackDao.get(dispute.getInvoiceId(), dispute.getPaymentId());
        var reason = providerPaymentsAdjustmentExtractor.getReason(providerCallback);
        var invoicePayment = createInvoicePayment(providerCallback.getPaymentId());
        invoicePayment.setAdjustments(List.of(getCashFlowInvoicePaymentAdjustment("adjustmentId", reason)));
        when(invoicingClient.getPayment(any(), any())).thenReturn(invoicePayment);
        when(invoicingClient.createPaymentAdjustment(any(), any(), any()))
                .thenReturn(getCapturedInvoicePaymentAdjustment("adjustmentId", reason));
        providerPaymentsService.callHgForCreateAdjustment(providerCallback);
        providerCallback = providerCallbackDao.get(dispute.getInvoiceId(), dispute.getPaymentId());
        assertEquals(ProviderPaymentsStatus.succeeded, providerCallback.getStatus());
        assertEquals(DisputeStatus.succeeded, disputeDao.get(disputeId).getStatus());
        return disputeId;
    }
}


FILE: ./src/test/java/dev/vality/disputes/util/DamselUtil.java
MD5:  4f155593c7b010f82ff79d3d5721056b
SHA1: 2fc10941196f6de9002d2aac8a23eca5e7c96a55
package dev.vality.disputes.util;

import dev.vality.geck.serializer.kit.mock.FieldHandler;
import dev.vality.geck.serializer.kit.mock.MockMode;
import dev.vality.geck.serializer.kit.mock.MockTBaseProcessor;
import dev.vality.geck.serializer.kit.tbase.TBaseHandler;
import lombok.SneakyThrows;
import lombok.experimental.UtilityClass;
import org.apache.thrift.TBase;

import java.time.Instant;
import java.util.Map;

@UtilityClass
public class DamselUtil {

    private static final MockTBaseProcessor mockRequiredTBaseProcessor;

    static {
        mockRequiredTBaseProcessor = new MockTBaseProcessor(MockMode.REQUIRED_ONLY, 15, 1);
        Map.Entry<FieldHandler, String[]> timeFields = Map.entry(
                structHandler -> structHandler.value(Instant.now().toString()),
                new String[]{"created_at", "at", "due", "status_changed_at", "invoice_valid_until", "event_created_at",
                        "held_until", "from_time", "to_time"}
        );
        mockRequiredTBaseProcessor.addFieldHandler(timeFields.getKey(), timeFields.getValue());
    }

    @SneakyThrows
    public static <T extends TBase> T fillRequiredTBaseObject(T tbase, Class<T> type) {
        return DamselUtil.mockRequiredTBaseProcessor.process(tbase, new TBaseHandler<>(type));
    }
}


FILE: ./src/test/java/dev/vality/disputes/util/MockUtil.java
MD5:  7ada9028d296151d20c12f2013618466
SHA1: 1be7bf17a1d9b6c0b3c81b30a93a53e3707e84bb
package dev.vality.disputes.util;

import dev.vality.bouncer.ctx.ContextFragment;
import dev.vality.bouncer.decisions.Judgement;
import dev.vality.bouncer.decisions.Resolution;
import dev.vality.bouncer.decisions.ResolutionAllowed;
import dev.vality.damsel.domain.Cash;
import dev.vality.damsel.domain.*;
import dev.vality.damsel.payment_processing.Invoice;
import dev.vality.damsel.payment_processing.InvoicePayment;
import dev.vality.disputes.constant.TerminalOptionsField;
import dev.vality.disputes.provider.*;
import dev.vality.file.storage.NewFileResult;
import dev.vality.geck.common.util.TypeUtil;
import dev.vality.provider.payments.PaymentStatusResult;
import dev.vality.token.keeper.AuthData;
import dev.vality.token.keeper.AuthDataStatus;
import dev.vality.woody.api.flow.error.WErrorDefinition;
import dev.vality.woody.api.flow.error.WErrorSource;
import dev.vality.woody.api.flow.error.WErrorType;
import dev.vality.woody.api.flow.error.WRuntimeException;
import lombok.SneakyThrows;
import lombok.experimental.UtilityClass;
import org.apache.thrift.TSerializer;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

@UtilityClass
@SuppressWarnings({"LineLength"})
public class MockUtil {

    public static Invoice createInvoice(String invoiceId, String paymentId) {
        return new Invoice()
                .setInvoice(new dev.vality.damsel.domain.Invoice()
                        .setId(invoiceId)
                        .setCreatedAt(TypeUtil.temporalToString(LocalDateTime.now()))
                        .setDue(TypeUtil.temporalToString(LocalDateTime.now().plusDays(1)))
                        .setDetails(new InvoiceDetails()
                                .setProduct("test_product"))
                        .setCost(new Cash().setCurrency(new CurrencyRef().setSymbolicCode("RUB"))))
                .setPayments(List.of(createInvoicePayment(paymentId)));
    }

    public static InvoicePayment createInvoicePayment(String paymentId) {
        return new InvoicePayment()
                .setPayment(new dev.vality.damsel.domain.InvoicePayment()
                        .setId(paymentId)
                        .setCreatedAt(TypeUtil.temporalToString(LocalDateTime.now()))
                        .setPayer(Payer.payment_resource(new PaymentResourcePayer()
                                .setContactInfo(DamselUtil.fillRequiredTBaseObject(new ContactInfo(),
                                        ContactInfo.class))
                                .setResource(new DisposablePaymentResource()
                                        .setPaymentTool(
                                                PaymentTool.bank_card(DamselUtil.fillRequiredTBaseObject(new BankCard(),
                                                        BankCard.class))))))
                        .setCost(new Cash()
                                .setCurrency(new CurrencyRef().setSymbolicCode("RUB"))
                                .setAmount(100L))
                        .setStatus(InvoicePaymentStatus.failed(
                                new InvoicePaymentFailed(OperationFailure.failure(
                                        new Failure("authorization_failed:unknown"))))))
                .setRoute(new PaymentRoute()
                        .setProvider(DamselUtil.fillRequiredTBaseObject(new ProviderRef(), ProviderRef.class))
                        .setTerminal(DamselUtil.fillRequiredTBaseObject(new TerminalRef(), TerminalRef.class)))
                .setLastTransactionInfo(new TransactionInfo("trxId", Map.of()));
    }

    @SneakyThrows
    public static ContextFragment createContextFragment() {
        ContextFragment fragment = DamselUtil.fillRequiredTBaseObject(new ContextFragment(), ContextFragment.class);
        fragment.setContent(new TSerializer().serialize(new dev.vality.bouncer.context.v1.ContextFragment()));
        return fragment;
    }

    public static Judgement createJudgementAllowed() {
        Resolution resolution = new Resolution();
        resolution.setAllowed(new ResolutionAllowed());
        return new Judgement().setResolution(resolution);
    }

    public static CompletableFuture<Provider> createProvider() {
        return CompletableFuture.completedFuture(new Provider()
                .setName("propropro")
                .setDescription("pepepepe")
                .setProxy(new Proxy().setRef(new ProxyRef().setId(1))));
    }

    public static CompletableFuture<ProxyDefinition> createProxyNotFoundCase(Integer port) {
        return createProxy("http://127.0.0.1:" + port + "/debug/v1/admin-management");
    }

    public static CompletableFuture<ProxyDefinition> createProxyWithRealAddress(Integer port) {
        return createProxy("http://127.0.0.1:" + port);
    }

    public static CompletableFuture<ProxyDefinition> createProxy() {
        return createProxy("http://127.0.0.1:8023");
    }

    public static CompletableFuture<ProxyDefinition> createProxy(String url) {
        return CompletableFuture.completedFuture(new ProxyDefinition()
                .setName("prprpr")
                .setDescription("pepepepe")
                .setUrl(url));
    }

    public static CompletableFuture<Terminal> createTerminal() {
        return CompletableFuture.completedFuture(new Terminal()
                .setName("prprpr")
                .setDescription("pepepepe")
                .setOptions(new HashMap<>()));
    }

    public static Map<String, String> getOptions() {
        Map<String, String> options = new HashMap<>();
        options.put(TerminalOptionsField.DISPUTE_FLOW_MAX_TIME_POLLING_MIN, "5");
        options.put(TerminalOptionsField.DISPUTE_FLOW_PROVIDERS_API_EXIST, "true");
        return options;
    }

    public static CompletableFuture<Currency> createCurrency() {
        return CompletableFuture.completedFuture(new Currency()
                .setName("Ruble")
                .setSymbolicCode("RUB")
                .setExponent((short) 2)
                .setNumericCode((short) 643));
    }

    public static Shop createShop() {
        return new Shop()
                .setId("sjop_id")
                .setDetails(new ShopDetails("shop_details_name"));
    }

    public static AuthData createAuthData() {
        return new AuthData()
                .setId(UUID.randomUUID().toString())
                .setAuthority(UUID.randomUUID().toString())
                .setToken(UUID.randomUUID().toString())
                .setStatus(AuthDataStatus.active)
                .setContext(createContextFragment());
    }

    public static NewFileResult createNewFileResult(String uploadUrl) {
        return new NewFileResult(UUID.randomUUID().toString(), uploadUrl);
    }

    public static DisputeCreatedResult createDisputeCreatedSuccessResult(String providerDisputeId) {
        return DisputeCreatedResult.successResult(new DisputeCreatedSuccessResult(providerDisputeId));
    }

    public static DisputeCreatedResult createDisputeCreatedFailResult() {
        return DisputeCreatedResult.failResult(new DisputeCreatedFailResult(createFailure()));
    }

    public static DisputeCreatedResult createDisputeAlreadyExistResult() {
        return DisputeCreatedResult.alreadyExistResult(new DisputeAlreadyExistResult());
    }

    public static DisputeStatusResult createDisputeStatusSuccessResult() {
        return DisputeStatusResult.statusSuccess(new DisputeStatusSuccessResult().setChangedAmount(100));
    }

    public static DisputeStatusResult createDisputeStatusFailResult() {
        return DisputeStatusResult.statusFail(new DisputeStatusFailResult(createFailure()));
    }

    public static DisputeStatusResult createDisputeStatusPendingResult() {
        return DisputeStatusResult.statusPending(new DisputeStatusPendingResult());
    }

    public static InvoicePaymentAdjustment getCapturedInvoicePaymentAdjustment(String adjustmentId, String reason) {
        return new InvoicePaymentAdjustment()
                .setId(adjustmentId)
                .setReason(reason)
                .setState(InvoicePaymentAdjustmentState.status_change(new InvoicePaymentAdjustmentStatusChangeState()
                        .setScenario(new InvoicePaymentAdjustmentStatusChange()
                                .setTargetStatus(new InvoicePaymentStatus(InvoicePaymentStatus.captured(
                                        new InvoicePaymentCaptured()
                                                .setReason(reason)))))));
    }

    public static InvoicePaymentAdjustment getCashFlowInvoicePaymentAdjustment(String adjustmentId, String reason) {
        return new InvoicePaymentAdjustment()
                .setId(adjustmentId)
                .setReason(reason)
                .setState(InvoicePaymentAdjustmentState.cash_flow(new InvoicePaymentAdjustmentCashFlowState()
                        .setScenario(new InvoicePaymentAdjustmentCashFlow().setNewAmount(10L))));
    }

    public static Failure createFailure() {
        Failure failure = new Failure("some_error");
        failure.setSub(new SubFailure("some_suberror"));
        return failure;
    }

    public static WRuntimeException getUnexpectedResultWException() {
        var errorDefinition = new WErrorDefinition(WErrorSource.EXTERNAL);
        errorDefinition.setErrorReason("Unexpected result, code = resp_status_error, description = " +
                "Tek seferde en fazla 4,000.00 işem yapılabilir.");
        errorDefinition.setErrorType(WErrorType.UNEXPECTED_ERROR);
        errorDefinition.setErrorSource(WErrorSource.INTERNAL);
        return new WRuntimeException(errorDefinition);
    }

    public static WRuntimeException getUnexpectedResultBase64WException() {
        var errorDefinition = new WErrorDefinition(WErrorSource.EXTERNAL);
        errorDefinition.setErrorReason("Unexpected result, code = base64:0J3QtdC00L7Qv9GD0YHRgtC40LzQsNGPINGB0YPQvNC80LAg0LTQu9GPINC00LDQvdC90L7QuSDQv9C70LDRgtC10LbQvdC+0Lkg0YHQuNGB0YLQtdC80Ysu, " +
                "description = base64:0J3QtdC00L7Qv9GD0YHRgtC40LzQsNGPINGB0YPQvNC80LAg0LTQu9GPINC00LDQvdC90L7QuSDQv9C70LDRgtC10LbQvdC+0Lkg0YHQuNGB0YLQtdC80Ysu");
        errorDefinition.setErrorType(WErrorType.UNEXPECTED_ERROR);
        errorDefinition.setErrorSource(WErrorSource.INTERNAL);
        return new WRuntimeException(errorDefinition);
    }

    public static PaymentStatusResult createPaymentStatusResult() {
        return new PaymentStatusResult(true).setChangedAmount(Long.MAX_VALUE);
    }
}


FILE: ./src/test/java/dev/vality/disputes/util/OpenApiUtil.java
MD5:  e627f16cf9a344fe4defadc355b34452
SHA1: f3f1acd834e45c8e236238f5b235c23102b262f8
package dev.vality.disputes.util;

import lombok.experimental.UtilityClass;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;

import java.util.UUID;

@UtilityClass
@SuppressWarnings({"LineLength"})
public class OpenApiUtil {

    public String getContentCreateRequest(String invoiceId, String paymentId) {
        return String.format("""
                {
                  "invoiceId": "%s",
                  "paymentId": "%s",
                  "attachments": [
                    {
                      "data": "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",
                      "mimeType": "image/png"
                    }
                  ],
                  "amount": 100,
                  "reason": "string",
                  "notificationUrl": "https://webhook.site/bd6cb94e-4ce0-4943-9230-65c466aa03a8"
                }
                """, invoiceId, paymentId);
    }

    public String getContentCreateRequest(String invoiceId, String paymentId, String notificationUrl) {
        return String.format("""
                {
                  "invoiceId": "%s",
                  "paymentId": "%s",
                  "attachments": [
                    {
                      "data": "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",
                      "mimeType": "image/png"
                    }
                  ],
                  "amount": 100,
                  "reason": "string",
                  "notificationUrl": "%s"
                }
                """, invoiceId, paymentId, notificationUrl);
    }

    public static MultiValueMap<String, String> getStatusRequiredParams(String disputeId, String invoiceId, String paymentId) {
        MultiValueMap<String, String> params = new LinkedMultiValueMap<>();
        params.add("invoiceId", invoiceId);
        params.add("paymentId", paymentId);
        params.add("disputeId", disputeId);
        return params;
    }

    public String getContentInvalidCreateRequest(String paymentId) {
        return String.format("""
                {
                  "paymentId": "%s",
                  "attachments": [
                    {
                      "data": "iVBORw0KGgoAAAANSUhEUgAAAPsAAAFlCAYAAAAtaZ4hAAAACXBIWXMAAAsSAAALEgHS3X78AAAgAElEQVR42u1dPa/kVnKtNhRsYMDDxgYODHjAdrDZCmADiowZAeRPYKdWxE6VkZl2MzKxlZLROGX/AQMkMDIMGBuQWG1sdK8MK1BgkAoVmQ5mzt3i5eVXv35v3kcd4OF1s3kvLz+KVbdu1alN13W/I4FA8NzxbtN1XSfXQSB49vjyr+QaCAQvAyLsAoEIu0AgEGEXCAQi7AKBQIRdIBCIsAueCuq6losgwi54roiiiLbbLW02G9rv99S2rVwUEXbBXXC5XGi/36vPm81GadLNZkNlWap9T6cTbTYb2mw2tNvtiIjI8zy1LcsyqutaCel2u1V97fd7td/hcOgdVx/L5XKhsiwpz3NK05TCMCTP80bHjDbof7PZ0PF4VNvx8uB9CB4Gn8kleFyA1vQ8j/I8J8dx6HQ6ERFRWZbkui4RER0OB2qahizLUgJk2zbxgMjtdktFUZDjOFTXNXmeR03TUNu2dD6fqa5rOhwOFIahUVtjW9u26ribzYZs2zbuxz/btk3n81ltxwspyzIqy5KqqpKbLZpd4HkeBUFAvu8rIfd9Xwk9BAqCjrk09sc+lmWR4zhEROQ4DlmW1RNM/Mb7mUKSJKrNNTidThRFERVFITdZNLvgcrmQ4zgUhqHalmUZNU1D2+1WCbKuXS+XS2/b2Lyab+fTApjeRERFUQz6h7BXVXW1CR5FEZ3P58UvF4Fo9mcNy7KoLMueCY3t3KS/K3a7HUVR1NPUXdfR+Xw2CnMURb0XEGDbtpqL6y8fzNnxUrEsi7Isk5sswi6AQMRxrAQOwgFnXVmWZFnWQMB0oTPtc7lclFY9n8/UNA3Ztt2zFGzbHvR1uVwoSRKjsBMRpWnacxSin67rqOs6Nd+vqkrN2QUi7AIiCoKAbNumKIqoLEtK05S6rqOqquh0OimB1effXOtbltUTeAi6bkKbTGr+UgDiOJ4cL6yCORRFQYfDQZbvZM4ugJDled6bQ0OgISR5nqs5PDzfWHqDti2KQq2LW5al+rEsS2lh3/fVSwFtwzAcvBi4Vp+ac+M33l8QBGq74zjKchGP/MNCyCsEgpcBIa8QCGTOLhAIRNgFAoEIu0AgEGEXCAQi7AKB4PEI+1T65S2w3+8piiL1vSxL2m63o+GhbdvSdrs1hmrq6aD3BZ4qylNIBYInr9lN6Ze3Qtu2lCSJ+p5lGaVp2svk4hiLwuLpoPcNpIp2XUdhGErct+B5mfE8/ZITKEDrJ0nSI1Dg3/lnnSyB6EP0FbR7XdeKfGG32/WSM5IkUTHcOvR0UK59YY3oxAq73U79cQIGnN9utxskdejwfZ+yLKP9fk+73Y72+706Fn8RIXJN7xPH5BYUtuH7brebvYYCwSi6hTifzx0Rdb7vG38noq5pmk7vcuwQ2B+wbbtL01Ttb9t2R0RdURSD/dM0Vfucz+fJcfB9TJ/DMFT9pWnaBUHQ2bbdxXHcWZbVG2NRFJ3rur0xoz/8xvvCOeR53nVd17mu21mW1Rsv2qGv8/nc2bbd69+27c513S6O48lrKBBM4O0qza6nX3Lo2VOY25u0L9+fw3VdCoJAaXceg82nDEEQTE4z1qSDnk4nlZXluq7S3CBZ4GMYS+fEtONyufT6QkIJn1ro5zzVJ7+OlmUNss5M11AguIkZr6dfnk4nZWbPPbBL9w/DkJIkocvlovjOQIU0R3pgSgddApjwmKLoL4/9fq/GbWrLTXWTeX86neh0OvX6nurTBDj/1l5zgeDqOTtPv8yyjPI8p/P5rDQ4fwB1rWXa36TxIRS+76uc6DzPZ8dmSgedg+M4akzn81lpzzRNFRkjEVHTNMYUTjjo8jzvWQb4b9s2ua5Lh8NBORvn+jRdE9d16Xg8LrqGAsGd5+yO4/Tmi0VRdESk/s7ncxfHsfqepungu74/4DhO77v+uwmmNvqclu9j+lxVVWfbtvqL41j9VhRFZ1lW5ziOGjO/BvrxcY1s2+4cx+mCIOjiOO7yPFdjwzxb75N/168Rjuk4Tu96LrlGAgHm7JLiKhC8DEiKq0Agc3aBQCDCLhAInrmwj5UTWrt9DDza7Xg8yt0RCG6JNe48y7K6qqq6ruu6qqpUNNja7WPgEWkrhyYQCG4VQTdVTmjt9iXAGr3EmgsED2zGLykntHb76XRSkWQ6UJggCAI6n88UBAEdDgfVjuhDkA76Q3BLURSUJImx2CD/j2i5MAxV4E5d12pMU1FxAoE46FYCMfBpmg4EnahftfShYs1R8dRxnF7KrUDwYoR9qpzQ2u3QzpZlDaqPwmQfC499iFhzvHw4mYZA8KKEfayc0NrtEFpkxfGEFdQg833/k8WaI6FmrLaZQPAkscadB486ERk97Uu3A8j5hpf+McSa8zx0gUBi4wUCwVODxMYLBDJnFwgEIuwCgUCEXSAQPCdhT5JEhZZmWdajZsay1eFw6NE3ExEdj8dBogsPV8W+bdv2wl/XrHdfLheVfPPcQmAR7jv2/VPDdC+J+qHMkuD0CbHWfw8qKtAdx3E8oDhO01RRTp/P586yrC5N0x4NM6dd1tsFQaDol5Egs5QyOQgC1S+nZX4O0KmzTVTajwX8GeBLrjo9t+CRUkm3bUvH47EX3sqj4oCyLFV0G+iO9Yi3IAgG7K/Yl9NAQ9Prx0AJqs1m0ysgwUNsuQbkGgfVZ7bbLW23W0UDDQ2EKDzeDgk5erINvo+1mdO+m81G/Z4kCUVR1Otjiebm5wKri49LP7clyUCe56k2unW0ZHyc5vqWlYMED6TZm6bpiqLoaUwUVSCiznXdrmkaowYijRzRpHVd1+0VVKCPgS56MM6U1jZpdj6eMAy7MAx7QTNEpAJ2TJpUP5Ze2AHWDvbjbea0bxAEXRiGKsgHBJi8rznNrp+LPi69wMSSwhPo03Sdx8an30vdcnNdV52r4AkUidC1pu/7ir7ZcZyr4smhWeq6Jtd16XQ6UVmWVFUVxXG8ap6HIhNjcfKu61Jd1z0aZtu2KcuyQV05k9WC/blGw2dsn+O318cLPwcScKb64NYFP65pbPz/2LmZkoGWJBKN0VjjXnKrDZaF7/sUx7Fo2KfqjXddV70AYJrjgTUJGYAHm4hUmikEO8syKoqCHMehMAxXVT5BG6TG3hVc6EzJNrvdjrIs6z38uqDyWnKm8UJIuECOCTtSebuu63H1o3/Lssi2beO4dIwlA6EPTF3WgKcMn04natuWDocDpWk6WslH8ESEXc9Ph/BDW10uF2rbVhU+BLIsG1gJeMCRDac/lGsshTENYnoZXS4Xow9B12ZEw2Sb8/lMVVVRGIajGhEFKHg/JmtEvx5Lr79t2+oYVVUNxqUnG0GDTyUDxXFMlmUNXpi4fmtelLwsluAJeeP1ghGYj5NWtMD3/UECTBAEar8gCJR3Ftv0+S62x3E8KBppKlrRNE0XhqGah/JEGj7GpmlU4UasFPBj8oIRvJ+xZBsk6ky1wT6m4pd6IUr0gcQgYsk+psIaQRB0lmWppCL9mPq5LSk8gf/YF74T0hKLfN9X40eCEu57GIaqL/36Cx5+zv6kUruuXUZ7bEtU+nlUVdV7cT3mZT8+9ue2tPnchf2zp2SFXLuEs8Zh9tDn4XkelWVJRVE86msP816/lo/t2grGISmuAsHLgKS4CgTijTeZARrjalmWahuPaEMM9Ol06kVy6bHTWFsfKyRh6hPj4N5l/Tg8QgyfTX3pY0mSxDge3nbtUpTgE5ms2jNyn3gyxU3WRM/RR9omHv1FE5FWY55X7jCbKiSh98k9vjwSSz8Ob8cjvUzOJH27aTx8H3ivBY8XpmfkoXIW6PHSmb1dzRuPmHX989j+Uw6ctYUkeKQbjr3kOGvOcW48S4N7BJ8OZVn2nhFd+yKfQrcwEZgURdHVxUTWFDfhFqleyOQ+ipssFnaEmMI00kNOTYIz9fuU4IxttyyLyrKkNE1VcMqS46x9oZmOy/eRxI7HjSzLes8I7huiD23bpjRNVRBR13WUZRmFYUjn81kFf00VExl7VtYUN/F9f9DntcVNliihVZrddd0eb7vv+z3Nx+e2t54v1XWt5vPQvmOWxVh8913Gh7amDDzB4wG39KaeEZM1gCg/Hvk3lj9gEq67FjeZE9i147mTsBMNizTwA+Et2XWd4oWfwlwhCS5k+/1ehcDC7CrL0tgH0YdCD7pDjY/PFL45Nh5YD13XUZ7nUinmkWt1/RlZCp5fgGd6qpiI3nZtcZO5PseU3rVtV2e98bkQLoopdh0CO/XGmSskoQsoTPiu66iqKlVVxnScIAio67pVyTBLxiPz9sc/X9efkSVwHEflB1RVpZKBpvIHOK4pbjLXp8liXTqeO3njeb43z4P2fb/L83wQAw22GWJx73pMN/d4k6GQhCn+Xff2c++rfhzeh2l8pmOYxsPbmopdCB4Pxp4R/szhM7/3uO/IL1iSP2B6nvWcjKniJvy5JVbAhK4obrIgHFyKRAgELwQSQScQvBSIsAsELwSfySUQPGf88MMP9MMPP9ykr1evXtHnn39ORETff/89/fzzzzf9/Vq8fv2aXr9+fTsHHXcQwGH1UI4q7gAJw7BzXXeWFIE+kl5MOTr4vtyRx48z57DTw3mLolh0Hvw7d8rAcWhyJqZpOqg4q5OCYDwg1cQ2kIVOVdV9jvjmm2+MDq9r/t68eaP6ffPmzc1/v/bvm2++uR8qaaIPOdh5nj9YJBmOm2VZL/cby3JpmvaosECdhCgj0DbBF8mXzjhBpuk4nudRURTUdZ36zo9tWRYlSdILmJg7D/07j+4CTTeWGzmXW9u2FMex2h4EAZ1OJ7pcLmrb+XxW1N3YFscxRVFEnudRVVVqWeo5FdAQ3IMZj3A9rLcjFNBxHKqqSnGfE30IbGnbtvc9yzKqqoqyLFNrhQh8AefZdrsdrB+eTidKksS4bu66LiVJokIeERs9h8vlQlmW9dbR+XHWxMrzeOxbM6jyCEX9Bavz8eM6Iv7BcRz18rNtW11T27bJcZwXFRH493//98vMXYaff/6Z/vSnP03u8+bNGyIiZaLrn6e2ERH99re/pVevXq2envz3f//3uguwxoynj5xjY+ubJn410njjYGYS40Pj1WXCMFS8Zkt558HjjjHoVUd4VpKewZbneW8c/DhznOnIkgM/u+n8p+ix9OOSllWoZwKOcfT7vt85jtO5rqumERgTv2f62PRpxXM34xeauz28f/9+1gy/Brz9+/fvH+K81vPGm+J6oSn0pJQxfvEkSYxTAMdxqK5ryvPcSH/E2Wl17QazPYqiRdoKZrduAUwdR7cK9Fj5JfHYJt53or9QRPN86O12S57nKU09xtFv27bi2Mc043g8Up7nlOc51XWtLA4cW+cOEIgZPxCEMAzV3O90OtHxeByNTx8TkiRJqKqqXtmmOWCOyXnqIXCu61JRFFTXNe33+0GigMksPh6PinZ57Dgm/nseK38+n+l0Oqm5L9IYp6YRfHpiIsJAEo9t29Q0jfIhQHiBIAjI8zwVQomXJdo7jqPGAL9CURS9a4M48JeIt2/fTv7+7bffjprdRERfffUVvX37ln766SfV1+eff07ffvstERF9/fXX9P333w/MePxuwvfff09ff/315Li+++67h5uzg189iiKlhV3XVQ8uF46x7LMxYcQcE0UF9AcRDjLM2yFw3DJA/P6csINP3QR+HLzIeLUXfVzIBgyCgOq6Js/zevXw1s7Px0gd+W/g6Ie1xV+AJt59vU+eQfgS8e///u+zc/UpfPXVV0r4vvzyS6Pgzh3DdMy1be5VsxMR5XlOm82m550GYCrCIad/h3XAs9ugoS3LoqqqaLfbqSIF/LiO4yhTVTf1wdLq+/5gimASHu5EmzpOURS03++VoGElgI+5bVu1HU6vqetnOi5elkgb3m63vWxCjEM3/W3bVkQMuDeWZVEQBGob2vMMKdu2RzO0BM8Un9qB8hy5x+Go439CZfW4HHQ0s3YNp9kSB9379++79+/fd3/84x+Nv//Lv/zL5O+mY4393cVB9ygi6J6bKWlZFkl+kcz/+Vx9bp9H56C7D8CTLBA8dfDQ3F9++aU3fyfqh8u+SGEXCJ4L3r17R7///e+JiOibb76hP/zhD0T0l1WaN2/e3MmbflcsXmc38a5zxkvsM/Yd7bE8xreZ+OR1jPHLc/53rFHzfRHhZ2qvH9e07oz18LIsjcfn7bfb7Wh7lFXW+een2idJ0rtWaM8dbUvbc3bVNVRGgueDVZqdL3VtNhsKw3A03lv/zj3o+jbf9ykMQ9rtdlQUhXFJDJ5xBN54nkdxHKu4cOyTZRlFUURVVZFt23Q4HNQ2vX3TNGoZMMsySpKk56HmKw1YisMS3G63U8cdm5/r7RHDb3CSGl9uURSpa4Ey1AjJTZKkF0evA8ujaJ+mqVqlwLr9Y68vd5/45ptvJn+fC6s1rbP/+te/Vv3yOTq2zfX5+vXr2XF9EjN+DX0zj6eHRuHbTNhsNkq4kATCY9SR7MHjwoMgULHuGB/qwpva83VrnaGTc4fhvymufAy8PY61pkb58XikOI5VNJ9t21TXNfm+v4jG+3g8UpqmihyTL0cKQy7R7373uzu1N62zv3nzxtjv0mO9fv36zuO6iRmvY6qYg27+6/S3Y5S4HFhvxsOpP9zgsOcPMZI+OLDN1J6PP0mS3osHwsLHbBIqog+RaNvtthdmy9vjPI7HI+12OzocDr0pg94e4cR8PGEYqmkHEn7G2kOTm14uSBi6NuhH8IRxzXp4VVUqYYS0dUC9frdlWb3EFNO2uTrqYwkpZEiOMY2BDESUOBbPeef54fhs2g854efzucvzvGuaRh1nrL1t24MkFZBl8vam0lXoB/n1juOonHzT8U3XjSfNvNR1drrnfHYayTHHtr/5m7/5pPnsq7Pe8FcUxUAIx76nadojvtC3zQn7WDad67pdnue9Gl+u6/bGwDPi5urQIZNMv5iu6xoz2MZeVqb2S84VAq23x8tVf1nMvSz1LEN+rUTYH17Y+TP46Mkr5oosjAHFJDhRhGkbx+Fw6FX34PHeiPXGfBxAHbi2bZXZjW2m9mPhq5w4AqWCdOcZ35+b+vwa8faoBgvz35QReLlcFFEGiCi4r4Dz2U8df2zatSTHXyBmvJHOSd829x2msr4NGovnV+sm+hi/PKdkAn0T3xdmq6k95+22LMtY9RNj4jnntm0P2tNISCzac0oonPNce379TJRUS9ubrA1cK8HdMBZOq1uRdIfc91tVcRXeeIHgDtC98aagGR438gnF7UuJoBM8e2E0CeBXX301WPd+9+6dCnfF7z/88AO9e/dutP2rV68ULdWvf/1rtXT29u3byXj4uWO9fv1aLe/xffkyHX6/uRkvEDwnB52JCmpNJpqp/ZIMu6XHWsNUu9SMlyIRAsELgZjxgmeNMVM6iiL61a9+1dv2D//wD2p//P7LL78YQ1j/+Z//WZnsc8ktaP+///u/qn9+rKWhuRw//vij2vbVV18tM+nX2AGkrf2u8cbzwhL6NlMxBx1j3njeBiysJs8z96hjPRqBJtgP3njf9wfMrGPH5/tOrRDo1xErDab2fExzBSJM5z+3QkEvdM197FleanqPmfxLCSW4mT73+5yZfu/kFVj3RSJGHMefNBEGhIy6hxPfL5eLSkBBrDlPJCEitY3oLwSMnHzicDhQkiSKsFFPxMHxkOE3lpyDGH6eHIMYAd6+aZpeAY7tdquucxzHxhBjfv5ZlhmPz8f/ksBzzBeXSTI4+YjG89Hx+08//aS2/fTTTwONzwko537/5ZdfjBbDnUgw7kIltTSCjtdzN20zRYBx7TcWQTfH0+77vtKA4KTvug+lkeI47tI0HWhuPQptKgKP87RPRfXhGOgLx/B9f9Bej4pDWDEPwdXHoZ/zXFSh0FJdR1tl0rZrnGq0IIJuzrF4F81+lYMuSZJBFZIx3GcizFQiClG/WoopkSQIAmrbljabDe33eyqKglzX7fG+t207mkijbx9LzuG59zwaT89e05NzkBmI64Dxe57X24+fPxh6+fHB9X84HGi3241GLQrEQdd78EGQgLx2EFDwB5aDF5bgbKr6Nh1LmU9BZd22Le12OyXcp9OpFx662+3IdV2K45iOx6Pily/LkqqqorIsFTe753kURdFN00CPx+MkfbX+gvQ8T72Q8PLzfZ9c16UoiiiKIkrTdHD+U+GyYRgqqu4oim5epuoprLnDqYa17devX6t18h9//FH9/sUXXwwceGvW0TlM5Z34dGCOPhplq3755Rd1/B9//FGNe/HU5BrTCObvp06EmUoEganOHYF6Ioluhutlp9aa8ZiemMx4MiTH6GY8kmscx5msBjvGyIusNtPxdcfpSzHr77rOPmfyL2WfXeosvOZY97rOvjSXHbivRJipRBD+mfPT8/+mYgqmKctYIg1PxEGlGFNyjuu6xuQYXnkW7fFZTzTi1xsFIkwWAe+TH7+u616VWkmKETN+FFEUKQ82L5Ywljmmf0dhCdu2B9tQ0kmvpsoLRaAgBS/WwKvIwrPOH3zMXS3LUh558NRB2GCyo31Zlr0+YUo7jjM4PubDKBbBvfWY2gRBYKyyit/09mC14VOjpmmMBSJM54+qNPrxUXiCiFS5rJeGN2/eDNbR59bZx9bR3717R999911vHZ6b03xt3NQXLw91PB7pb//2bxdRXHHP/b2uswsEz8Ubf806+5yHfI2ZviZc1uT5p/vOZxcIBC/EGy8QPDVwc5qb2e/fvx/sO/e7KWz1+++/N1Kff/PNN6vJIz///HN1XO69f/v2rfLY4/d3797Rv/7rv4qwCwRcgE1LU3PLZqbfr43AW4pXr14tHtc1xSauMuN1Z9FcsQgOvdAEvMN8O0I+TUURuJfcdAwUZTidTr3iCfCkHw6HQVEIU6GFsaIUpvamMZnOCc4YvVAELx4xdU3Gxnor8GvGi1hwwKGI50AvsjH1HGw2mwH7rwlz13Gs4IYJP/zwg8ppv+sfD2f9/vvvB9uWAH3x8lDAzz//bDyuad+rsMbZgfVp/DmOoxJiptbbx4BQ0DiOB6GzQRCo9eI8z3sJJSBg1I+B9fDz+dxbr0fIKA+PBcutKeQUY0NiCkJpx9qbxmQ6J4zDlOSz5JqMjfWWySE8zgDxDTxMF0k2priIqecAFFom6i/9WsxdR87Ue+06O92QcPKuSTc3csDd1kHHq6Kcz2eK43hUg+PNbprPAHxNXF+yQ1EEaFkeGYakFl3j8D75/lguK8tSLYPx4g06lhSl0NvrYzKdk17UAjAlp5ja3yd4TIO+jYcP889rUJalSkKaejbmruM1BTcEK+fsCNjgQqSvjeuYYjRFkAeP+z4ej+S6LuV5TmEYqjpwlmWpDDdeQEEvyoC1eF3AkPHled5oLPput1OZZfp5Yt+yLHux7WifZZlxTPo54eWFcwrDsPfQmmLheXts52NdmqOwRNj1c8ZLFi9SfDcFH80hyzJqmkZNPUzPxti95dcBL4Lj8ajyEBAGPAeEna7Bzz//TH/6058m94EjjlNF8XV0x3Hor//6r3tt/vM//1PNvz///HN69eoV/dd//ZdaW//uu+8GYbRjFFmLQ3fXZrrp5tsYV/qUGY+8aphnRVEosywMwy4IAmNRhLECCqaiDOiLM9bqZie+TxVq4PuSxnirZ/7xz2PnBDMW5qoeQsynTHp7mMNjRSHuAtM5p2naBUGgQnARgoypBs+7d1139Dng4c6O4xhz6ZdeR2TwmQpu3Cjv++qstjXhsmuy3kzhsnSfRSL4fNGUinrNnB1FGfSbToxumd9QTspAWgEF0uLOi6IYxN6PxaLrQs0FcS4WfmxMpgfZ1B4EH9fGwptyCa6BKf8gjmPlO/F9vxe7z9Oc5+bsOjmJidBj6XWEr2jpdRBhv3LOnqap8nbDGzpVMwxplVNmPp8b6vNaPZY9TdNBAQXHcYxx53o9NEw79Fh0U3y94ziLY+HHxmSKZddr0WE+epdY+DUFNqdguhfc3MZcG3kRa0x5TH+6rqOqquh0Og2ejaXXEeHAcwU35qCXCNf/5pa2vv32W3r//n3v7ze/+Y1q/5vf/EZt//LLLwf989/H4gPw+7/927/RZrNRlNVEHzLp8PtiltlrtAA3jafoqHRTc6woAzcHYSmM0TCNHVMfm+M4Rm2CDDRToQg+tZijoeLbTGMynRNfMaCP1FAm01c3kYnVlaOZohR3Ae8fVguOwclGYNbr15hTjvHrYbKSpqYhc9fRVHDjFuGyZMiKuwVVFN2QAovukPUmsfECiY2/Qtj/+Mc/du/fv+/9/dM//dPNhP3Pf/6z6veLL74YtP/iiy/U73/+858XCbtE0AkEV+Drr7+eJZ1g1vPq/t+9e0e///3viehD6O0f/vCHwQoAzPqlobmSCCMQyDq7QCBYAtBDcfD1fK518ZmXdAIF1hjtFKfLAu6VlsrkSIIThTtqwNGuO8/g1NLZVKecYboD6FbLTC8BOh+9iZufLzuaKt/qDkE91NXEb8/v2RTNmGVZ6rcpnv2x/nibqWXe+5qzXxsue00++ycp/8Rrj5/PZ7Us0rYtnc9n6rpOLU3xJRMwwYRhqBI9oihSS2PghO+6rhcFx/u91RLTSwDnoz+fz4q8EvfO931K07S37Oh5HlVVpeaXiArky5pZlvXua57n6jcsp/ElNH6/OTjlGNh70QZEpKYlOfR3Op0UNz7OUfAJzHhdKC+XC2VZ1luvRdGCruvUWjePQ1/LcSfoYywHAGv6ZVn22HvxG+4d7tNcKK4pRJVvM8UxJElCtm33+AGxVs7bbDYbOp/Pxv6WjG0OppJOY2a4Cabc9nfv3qlwVk4VhWNx2ilTttzr16/Vvry8E6fL4mb8vdFSTUXJ6RF1VVWp3xAeiX0QnaYXjTBFRPHtt4wWe+4YCwtGyKm+Pj8XAYn7aSpSge6m8FsAACAASURBVDV43cSP49gYoWgKa+ZTDL6Wz9vy/sCi6zjOICrxoSLorjnWLSrC3uG8brv0xllbif6SIeX7vjLl12hsPYddcBsTf43Zm2UZRVGk+On1+6Pz27dtS/v9nhzHMR5H18in04miKKKiKKiua4qiiBzHUZbHWH+2bavkov1+v2h5C7nta7A2X/1R41aaHc41RIVZltVzwvCEGUTHjcVkw3nE88VFs69zzo3lAJhuObQlT8JBH1POL1NMPy0sGon7Cf58Pnae82/qbyzH4FPls5Mh0MUUCAMt/v79++63v/3t4lrwawJ0buagm8L5fKamaVTaYtu2ihuev8Udx1H0xqi6grkktAW2PWQ+93PCWA6AKY3VNG8G13yWZaNVY7C/ru2n0ppN0P0zGCOceKb+TDkGj8GB+6tf/Uqlm+o01QB+1yvEPDoH3RgnvEkoLcvqPSiWZVEURVRVlfLM73Y7iuOYiqKg/X7f42Q/HA4DggOYk4JpmPjoxxxmm82Gmqbp3QPf9ykIAsqybJDIhJx0rMbw+1NV1WBbEATGZCmMI01T8jxPtXEch+I47lWvNfXH20w9E7y8013BSzaZqrnO/T62LwT/1atXs2v2c79PYdNdE8v3ANDLN2N+KMssAsFV+PLRhsuOWQsCgeA6PFrNLhAIXohmFwgEt4UIu+Bq6LzwqCcwxScPp+sU0821/PuCGwm7qfADKKp40Qi+39h2/cbqlD3wwJoKSpiKJPAbb4rFNhWO2Gw2KtDHVKSBF4nYbDYqHttUnGDu+M8Z+rIZ/iOnoeu63vKa53mU5/koG2xZlhRFUa+vOI5VX0EQSGz8Q2h2U3KLvl2/6WPtgbEEDZ2PjC/f4LemaWYTKTi19Fhihymh43A4qOQcjM3zvAFX2tzxBdS7F0EQkO/7Rt74tm3peDz27vUa/n3BPZjxPLnlmram4gBI0NBvIs+OM4EHhOgkklOFIzjGtIyehGEqTjB1fAENhBb3ciz4Jk3TwTWG9ed5niK7PJ1OtN/vyfO8RSWlBFcK++FwGKRILsXYTTaxwY69xXe7HW23WzV/Q4DObrfr9aFrCaCuaxXQo6d5BkGgBPtwONBut+uZlcfjkXa7HR0OBzXvHDv+cwcvsqED0x1YVqjIwyvP6MEwlmUNBB3WXtd15DiOsiht26aqqiiO40FhEMEI1sbGg1VUz04jQ4GIse1jhSP0DCnwlevbeJEEECwURaGyp4qiGC0ckabpgERDL9KA75xRFrzpOpf92PFfCnQW4Ck++TRNjYzAS3ny5/j3BTdil51KbuEXeyz1da5whOm9Y0rH1JMpxhIpaKRwhGkMekKHiRqbRooTzCVyvMTU2qniEb7vd2EYdk3TDF7kpv31NNcgCLowDHsptURCknzzFNe2bSkMwzslHcAJo5MnmPq8XC6TSRUo6GBKpOCxQrvdjtI0pSiKBokdpoQO1DPD/BtTjCRJVNIF2o0d/yWC50rw5bCqqtRveZ7TZrMh27Yni0Rif708OBy2S2PjBVea8TzlFBqRF4TQtaJpu6k4wFzBB27Ck1YkAeWIiPHi6dOBscIRNFI+qmma3rGgqU3FCZYcXyB4DJpdwmUFgpcBCZcVCGTpTSAQiLALBIJnLuw8tnws+QDbQRc9B1PMvO6Bxfclxxc8DMZyHQTPRNgPhwM1TTOZfJCmKR2PR7pcLrPRZIhGq+u6l5gyFlO/5PiCh4PkADxTYedhjlyLQ9OWZUmXy4WiKKI0Tcm2bdrv972MMGS0EZHS+lg37bqOLpfLqDVgOv5YnP1LAs6fc7UhLdS0/XA4TP7Gryu/t9yq4hodGn632ykOu7IsexmD3EpDCPJut6Pj8UhJktB2u1Xhz/x+QhHoY8qyrJcyKxbGQlxLJc1RFEXnum5vH2Lhsaa22J//hn7GihzofUxFYb0UuK7b5XmuwlYRKkwfQ3n17XEcj7bhhTsQ94B7okc7onAED0tO07QLgkBFKyKkGHEHnDY8z/MuDMNezAV9jGlAf/w3Hp/Bn4W5yEzBjYtE2Lbde3snSTKILDPN+ab6WTInNyVTvDQ4jkN1XVNd1xSGofocBIFxOxhbx37TLSn93mIbzyzEdM11XVXeacm9q+u6t69t2+T7PpVlSbZtD5JipN7fA5nxnNudO862221PMGGKzwmh67qD1MTT6aRuMCc/4OGpguF1rOta+UgwnfJ937gdmWVjv005Z3Gv5+6D4zjkeR55nke+7w8ox7fb7WhGouu6dDqdqCzLVfzzghua8bxSi27q8eQH+hjGOmdqoQoJaSWgsd1kxpNWZljM+L75q0+fxrbP/Wa6dzzTjE+rxsz4sVLNZKj+o39GSDK/13pyDJ491BEU3LgiTJ7nyvGCHGIsg/G3Nyco4JaBbimcz2dVqbPrOpUwMVaMgh9/t9tR27aTyRQvBZwjYMnnqd/gRNXvXRiGKvmE1/QLw5CyLKPdbqcqyJRlqZx2IJxAwQpM0bbbLZVlqQpCbLdbpen5uExjAmEIaMCELOQeNLtAsMSRy5OaeDXWOcef4Ak46AQC3YkGPw535uEzrDJJTX3gZVrJehMIXgQk600geCm4U2z8WJEAouVc6mP7wRnEI6bmOOg/NTAuPbZ/Dqb9sY3z1yPCjW/bbrcqysx0LR+yPdGH9fntdqvOx8T9P1b4AdF9KCIxVlNgjL9fcENhN8Wmm4oEZFnWI/EH9bSOsf2iKFIhtN3HwgBLOOgfA8BMuwYILzadn+d5VFWVotnKsow8z1Oc9kVRkOd5o9fyodrzZ4Sff8d4+sHJbyr8gOcDz5bneaM1BUz8/YIFWOrKM62R6uvnWH9FOCankwIJJF9/HdtPZw9dS155Hx5mIlLrvzgX0GKRxqDL4wLQjjPiIowU+4M2C9RfxCiz+Hny62haZzddy4dq3zSNIoQcY3vFfnxtnnvt+T0nLaYDlGhN0wzo0QQ3XmdfQ6QIIkbAcRwV1aUnspj2A6njY/MyN01DrutSEARUFIVK44WW0jUMrBOQVWI9O0kSpRlRVQZaE9rMFG/gOI4KJdWPU5bl4FrqEYr32R7r4KaoOJj+/JxMhR/00Fn9unCLx8TfL7ihGT8m2KbsJhPyPL9TAATmaZ9yjoYXFB7Muq5HK8pwIcHDnuc5ua6rMr50gdADSp4Sxkoybbdb8jxPBcOMFX4YQ5Zlvb7x0jyfzxQEgWS93VrYTbHxXHshhh3b+L5jmnpsP1PyBdFf4uUf0xztmnj9MAxVpJmeVzDllwDltb4ftnMNV9f1IJHkPttPvZyapqGmaSgMQzoej+S6ruo7CAJlVej9ok9TRB/au647+rwI7iDsSx1jvu/3HHJZlpHv+wPnzdh+juM8mTBYJJxMAdofJaXQriiK3oOKJBB+zXkCEK4PMsa4eTx2LR+q/RJLxPQMIfnJdV11fF4zT58+gtMfY8L4JCPuhg46nbcdThgeGsl53pFTTURdEATK6aI7bkz7wXmH7SgbZOKmf+gQUO5Mw2fuVHMcp8ePDwcd2uA8LctSzrwxB935fO6qqlLbkPTDt1mWpcpUma7lQ7Y3PQf8fMbKhWFf3/cHfZrutYm/XyC88Z/UvPc8T5aFBI8FEkF3n5BsLMFjgmh2gUA0u0AgeE4QYX/C0GPqdVZYnQkW0GPO4VmPoqi3/XQ6GePY27btxabr6+RJkvTYX/U4dp5jgfZjcfDXHF8wgmvcenp1VWwjg4d1ikoJ+/B2CIU0eYa5F3bMi/wSKIrAyqpfHz2MeElYcZqmKlTV9DjEcaxYZ/kKCg+ttW1bhbaiKi6Oa9v2wFuuPxsIJ+ahswinXXt8wY1oqcqyVJoAPOHQCm3bqqCXuTVPnjjBXjrUdR01TaO4x7GtLEtq27aXlFFVFe33ezqdTr0Ejufu/UaNeFxnnO9U9Z0pfn2EpWZZZiSTMAXM8DgIXsee6EMYK1hqkfSyhiX2crlQWZYqYm7t8QU3MuOxlISHLI5jZa6ZbqAphBbx1lM3nAeTIMACwRU8Ss9xnEEo5XMHFwQADLFT13OMqTVJEhUYdDqdyPM82u/3vZeHHseOLERME4qiUPs5jqOONRfHDqURx7ESVh4Hv/b4ghuZ8chm0zPQEDDCu8LvnH9M/433AbPPsqye+QYzFWacPlxMHXzf7xzHMWbLPTfw64bP/HouNeP59U3TtLNtuwvDUN0v3/e7MAxVsQdMH2BC08esvDiO1bROZ6TFf7TnU4U0TTvLsgb3Szfplx5fMG/GX1URxvTAmYRdB09t5Pvked5LAcXNLIpCPZT8M7F0UyLqwjDszRefM3jlFlxDUDhfM2dHtKL+ojS1NdFK48XA/SbEUnR1QbRtW71cxnw5c8+g6fgyZ7+hsPMboWtl/SZN5TPzPxO7KG4m54P3fX9yX37jx479XADOdNJy6PGyNAn7HL++7/sqF507AbmmhzUQBIHaf8xBppcBw/1A7r/v+z0HGz83U32BtccX3EDYURuM/6Vpqjy6S8z4JS8EXbhd1+09iNDiMD2h2ec0w3ODviqix5Hz+H1+XXiOg2VZ6vrxfAQ+ZdNXWfT4dt1brlNG63Hs+suKPhJVmOLgrzm+4AbCbnrIdKYW/CGpYUzLog/+4BFjf+EPBK8Uw7UZlt74Q2rSGAKB4AaJMKaED0kCEQgeHW4TLmta45R1T4HgcUESYQQC0ewCgeA5QYRdIBBhFwgEIuwCgUCEXSAQiLALBAIRdoFAIMIuEAhE2AUCgQi7QCAQYRcIRNgFAoEIu0AgEGEXCATPV9h5xQ8dbdvSdrsdUEgnSdKr3DG239Sx6rqm7XZLm82Gttttj5ZY749XEdlut4Ntx+NRtT0ej72KJcDlclH11MfA2/I+nwJMY9/v92obzl2vPPMQMFWNueX1NnHpg0ZbB68+g2PySje73e7Br89VWMttAzrgMXZQUESZqn7wbWP7TR2LV4FBjfCx/uZODZTFeZ4bySxd1+3yPFdsrmDF1Tn5dK48036PEWNj12nCQQf20CSepucnjuObXW/w8oF/D/RqJvD687gmvCoNnpPHTku1SrO3bUvH45HSNFXbeCGIJEl6hRyAuq7Jsiy1fWy/qWOhUITjOET0oSoIti3pz9Q/NIipyEQQBHQ4HCjLMqrr2riP3jYIAqWR+D6wFqANdrsdRVE0qM223+97mjVJkp6Gg9aJokhZOKfTiZIkoe12S9vtlrIsG2hok9YZGzsHinVMaUeMabfb9eq1wRrQz0/XiGMw3Uu9QEYQBKpKkel682tgKqJhWZYqhoEiJJ7n0W63o+12q9rgmdPHB8uyrutVz96T0OxN03RFUfSogjmDrIkTXuc6n9pv6lgmHnPOm26iuNYLT/A3NawC27aNRSY4EeYYDbM+fs56ire+67q9+nUYCywdvbCCiaabM+eChRWWDyyaMbrvsWs8NnbT8cf64DzuOsMrfeSN189PfxbmgD50q2PJ9Z56vtAWxTCg6XHOuLa6taczGROrT/isNLtlWYO6XXmeK765sTJMekmfJeWaTMcag6m/PM+pqiqqqqo3t9tut+R5Xk9r2bZNVVVRHMeqDh1qnwVBoMpMLZ0LWpaltCTq1OEzzmkJR59lWT2tjLps0CK6xYR9UDYLx4D2g7UwB2henM+S89VLNtm2bTzHsixHS1GZnhvP8yhN09FnZup6L0Ecx71rYtLisEZ831d17Ha7HbmuS1VVkW3boz6sF+WN5w/4XaA/+PxGm+D7vhIECAARUdM01DQNhWFIx+ORbNtW43McR+1bFIWaKoRhaHzYeL9cMHzfp9PpZJwiwIyfM5G5WbrdbgdOIEwFpq4tro3ruqrwJYTSNHa8NFCgMwiCReWQYc6OjfXa5yZJEmqapnd/9FpxqGM3dr3nYNu2mrLhWUFdOQj24XDovXDwMg3DkBzHoTiOVYHJZy3sh8Nh8iSzLFv8Jp8TdsuyevMkbFuibfU5Fdo5jtObz/F9bds2VjblLxSu8bMsoziO1QvkcDj0zt1xHMrznM7nM1VVNTt2VLNFG34O5/OZiqJQVWynznXp2E33ae4Bxrkej0dlDelj5XBdd7IIpX4t9bb6mMMwHL3eSxGGoXqu8jxXL0a87C+XS++livuG647/j55R+VpPJip3mDzqvIjE1CFMdd6njoW5Nmn12ZcUnsA8mViRCRz7LkUm9DrymJNiDHyujfHDl8DPDZ/1SidYkSBWEQX7oTBiHMedZVnKP2HbtjrnqWusjx3787ko6rXxMcCvwcfvOE6vFh8fq16dBueI/6aqQWNVY9Zc76lz16vPhGFoLBDJ5/J8HHp1pCewCvP2XqmkT6cTZVkmJXVXYLfbUVEUT8O7K3hKuF8qad/3RdCvmK4IBPcBKRIhEIhmFwgEzwki7ALBlZjKEdExF0tv6ovngiBPYSo/ZBZSyVYgWI+5HBHTysdYLP1YXzyfxPf9Lk3TyfyQm0bQCQQCc44IEfVi8PWMzrFY+rG+2rbtRUcicGgsP0Q0u0BwDzDliEBDI47flE9Bhlj6sb5M303af0VGomh2gWAtxvI2XNcl27bpeDwOIi/HYunX5ICIg04geGQmvsk5tzaWXo+3QMjumvwQEXaB4J6A+TqSrHTBXRNLj0Qp7IvchWvzQ2TOLhDckU2Hx9PTxxx+U87IXCy9nm/CcymIcSrM5Yd8sth4gUDwaCARdALBS4EIu0Agwi4QCETYBYJHgiiKepz/fDlrrDbB4XBQbeDZXsJHr/Pn47uJRZeoz30/xaRLNF8fgfMIlmVJp9NpPe+d+FQFTzmSjUeU6THnptoEPLrtfD4rdp8lfPR6tBq+m1iCuVd9bZy9Kf4dzMdgvXUcZy2rkkTQCZ4usBYN7VyWpYobH6slwLnnwdZr4tBfwpM3BVgYS3gGl9RHALegbdtUliXVdb2ab0+EXfDokWXZaOmuPM9VMYi2bZXQWpY1SC6BiaxTb/OXBARsTero5XIZUFBzyu85pGmqQmZN7WzbVsSoPHBH5uyCZ4f/+I//GP2OOPQ8z6mua8Ufv5ZSeil43TceEXctndjS2PgwDFX1H8DzvFWU3SLsgkePf/zHfzR+h0b1fZ9836c0TWeLeTiOMxAQ13UHfPSmYhFEf+HU77qul6Zqoiq/hjt/rD6CbduqloHjOGrqsYTXX4Rd8GQQBIESsK7rlHnO48QhpHMalnPPXy4XatvWyKG/JhNtqi7B2sIRU/URLpeLEnKY9qv6F5+u4CmDc9WbcrvBHc+rtPq+P4gtN3Ho69B56B3H6aqqGvDK00cvPK9fMMdos6Q+QhAEaiUBdQNWeOQlNl4g0IH1eY44jo1OscvlQp7n0fl87s3rHyH3/5efya0VCIam9BodqE8dHiv3v2h2geBlQLLeBIKXAhF2gUCEXSAQiLALBAIRdoFAIMIuEAiek7AjoV9P9BcIBPMAEYbneUT0oaQUB0gsiD4kwvCEnAcXdsTqro0JFggEH4CkF8gQj9tHVh8RrY7SWyzseOOALgdvlSRJ6HK5qO36WwbpgNvtVl4AAsEVipMLOP98r2a8bdvUNA25rktBEFBRFJRlGWVZRmEYUtd1g1BB27ap6zoKw7CXiysQCKYBog0QVujEG2txVWy8zsxR13Uv7dAEx3FE2AWClZrddV1FnQUqKqTmro3Bv0kijDjiBIL7M+NRm72ua6qqStVpXyvsN3HQua47O5eYYv8QCARmWJalhB3fOcnmvWl2vEn4G8WyLArDkPb7fY8ih1eu3Gw2ZFkWVVUld08gWGExY47uuq5iz7lWad5riqspsV8gENxOZlYQZdx/iutjTeQXCB6r2d62rQqqmYLneavm7kJeIRC8DAh5hUDwUiDCLhCIsAsEAhF2gUAgwi4QCJ6BsPOidmMF60Gwr4fQJknSC7rR9zsej7N9E5Exs44Xso+iqFfxE0Xr8X2329HlcqEkSXr7ISLJNI66rlVW3+Fw6B37cDgYM/14hp+ek/zUcTqdetmMuHb8eqLIwtL7OgcEZ3F4nqfuuwn8ueD3kI/5cDgMnoFnizWldlCGBgXjTYXmXdftiGhQhseyrN42vl+app3rur3f0jRd1DfK79i2rYraT41bPxa2+b4/Og4+duyX53kXx3EXBEGX57kq3YMyPXEcd13XdUVR9H57DuDXP89zdc30a7/0vi49JhF1YRh2Xdf1yjmZgGcBZZd4GSWUV8J9R/+WZT3nSllvV2l2U5ge17RJkqiC8RwoToft+n5lWfZK7AZBoNL6AHzX+z4ejxTHMRF9SPLP83xy3KYgBNu2qW1b4zhOp1Nv7L7vU1mW5Ps+1XVNWZbR4XDolQbihQKxL7cuoPm5dZFlGSVJQtvtlrbbLWVZRpfLRVlTu92up1E5IxA0H9dy+B1tuFVWlqXSlLw/fTxj4PdgKqhj7L5yDX06nWi326kx8zHqsCxLZU6icqrnebTb7Wi73ao2bdvS8XhUmZht21Lbtuo5QEFEFEnkz8Cz5ly45hXhuq56w/q+rzQ83tp6gT2u6Uz76ftjG4dpX2hWbLdtu/N9v3Ndt3Mcp3dM7G/b9sAigcYxjYO0onx8bCgQSESDAnv0sbgfLCDedxiGXRiGA83Ev9PHAoP6OfDfq6pSY9GvmW3bXRzHAwusKIrOdd3e/vi89nHI87x3XrhW0Jpj95VfL9d1lUY1FWbU2/q+34VhqO4NxozzgtYviqL3vJieJ91KnDr+i9Ps0DS+7yttmue5erPztzgHyC34G34NjscjhWHY0yiXy4WyLFNvb6518jynqqqormuKoojatqXdbkd1XdP5fFbjhSYzaZEl81bHcSgIAsrzfJCrH4ahOrau+VAPXD8f/t22bcqyjHzfH9Wuc2GSURRRURS9/WzbNqYkm8oOz/WdJEkvLhvXvaqq0fn55XIhy7JUFldZlqu0aRzHvWttsjYty1pVcvnFYM2rwXGcriiK2f34G5K/ccf2832/pxnzPFdzKWgM/ue6bq/ELt/Ox2fSJFPWiuu6g3G4rtvTCkVR9Mbm+75RG8CXAAvIdE3GLIYxzZPneWdZVu83fv6m9rgejuOoMsC6tjNZMFNY4oeAFtavp2VZ6t7lea4+L9XssBQdx1HHwPlz3wxvY5rfm54Xk9X3IjV727Z0uVwGb8zD4TD5Zp7STlzT8TlilmW943Rdp/5s26Y0TSlNU7XtfD6TbduDvHocGznBU4A20Mfh+746d9PY8jw3akTHcUaPW5YlOY7T07C6xr1cLgPfBXwSOF+0wzXQkaZpb7WgaZrRbKoxjb/EUhvT4KbrCQvNdV06HA6z98WEMAyV5zzPc/UcjKV+WpZFlmWpNvAhcd/Ktewvz1Kz61oEc1KT550XrZ86BN+Pa+ogCBa1MRWyh8ceb27TuOFBx3fLspQGNo0D3lsi6mn1KStB3xeall+7OI7V9zRN1Rwbc15umfDVBvzx8+af+XUqiqKzLKtzHEe1w296W308GKfpHkxdTyJSvgb9esIPgf25f8N0b033GH6POeuCt+H3kHvmYRnwbc9Vs99r1tvpdKIsy6goihc/XVqRdywQ3AfuN+vN930RdGZKCgSfEpLPLhCIZhcIBM8JIuwCwZTpa4j3Xwoem8/74XkCU7kDWZb12mRZNhrjL8IuENwAWNprmmZxm7IsVVAV7wPLpmmaqpBo/IZAMaBtW4rjWP0eBAF5nkdFUVDXdVQUxSKuOhF2geCOGh8xEHqWpx6bzxFFkYpRmMsJQbQh79cU4780AlGEXSCYARJtuNYtioKOx6MKstKXVNM0NYbs8uQbvXCK4zgDsxwh3Z7nGUOakcAjwi4Q3BFj8f4Q8OPxOMi0HIvNP51OqyIGfd9XkaKO4/T4IK6BCLtAMCNwSHHWQ4rXpsPOaXL9d14FJggCulwug5Bm3dQXYRcIbgBuRmNuHYbhYgYe3QyfywnhL5PT6USu6xpj/BcHbHUCgWA0X58M8f6cTwCfTTH9Y/kKHKZcDPqYK6DnU5zP59EY/08eGy8QCB4NJIJOIHgpEGEXCETYBQKBCLtA8MAAjyDixLHmbIofH+O1B67ltwdjr/7dxNRL1OfXB4PuGOY47sHKi8g91ENYBfG5Cp4CwIaj88XFcTxg4B3jtTex+K7ht9c58vDdxNTLvepLOP1ohuMefHngL3QcZ5ZX8U7ssgLBp4LjOIpfsK5rxRdnCipZymsPLKlbcI0lQjRPWrKU4x5r9LZtU1mWVNf1av4+EXbBo4JulsOkDoKA2rZVZjJnQOLx43ogSpIkivacg8e7L4lRn8LlchmQXaKIxRLwOHpTO9u2yXEcKsuyF8wjc3bBs8TpdKKyLKmqKorjWL0ExuLHTbz2wBJ++zFwvwHm72tCVnUs5bgPw1C9vAAkxyzFZ/IYCZ6Kxi+KghzHUZq3bdueoCDfGxqwqipjXzB/EfOO/vBS0DU9B6fxhtPNpI0xxbhG+E3x77ZtU1EUdDgcVJGNOI4piiJjyTPR7IInCx4TDoHkc2Nof8SbLzVzx/jt11SUMaWeQtOvTZYZ47jHSwApsnhJrepf/LyCpwDOoU8sTt0UP27itUeNg6X89ktqFjiOoyr/kKGmAj/WXLWdJRz3QRCoWgSoqbfCIy+x8QKBjrZtB3xzcRwbrYXL5UKe5/Uq7TzSGgFfypxdIDCY0mt0oO6ce6w1AkSzCwQvA5L1JhC8FIiwCwQi7AKBQIRdIBCIsAsEAhF2gUAgwi4QCJ6csIO9Q2f1EAgE8wDrDQo2bjab3u9grCH6kPXGs+8eXNgRmL82AUAgEHwAMtwgQzxJBwQeRLQ6JHexsOONA24svFWSJKHL5aK2628ZzvUlLwCBYL3i5ALOP9+rGW/bNjVNQ67rUhAEVBQFZVmmUgq7rjNSBHVdR2EY9hLvBQLBNJBjD3YannN/Da5KhNFpeOq6VhxaY0kAjuOIsAsEKzW767rUqqLiYwAACRVJREFUti2dTifFO3e5XBZx691E2E3CLxAI7seM931fCXtVVXQ6na4S9ps46FzXnZ1LTFH9CAQCMyzLUsKO723briLEvEqz403C3yiWZVEYhrTf73vF4rEPHHuWZY1yggkEArPFjDk6r9V+rdK813x2E4uHQCC4ncysYMW5/3z2x8raIRA8VrO9bVsVVDMF8OQvlTFhqhEIXgaEqUYgeCkQYRcIRNgFAoEIu0AgEGEXCAQi7AKBQIRdIBCIsAsEAhF2gUBwT8K+2Wx62W1gqEmSRDHS8D/kr2dZRvv9njabDe33e0WzczqdBm0kXVbwFFCWZe+Z5vXU9/t9j9EJvx0OB7V9t9uN8juABcokF0mS0G63o+12S4fDYRX70+p8dt55FEUqNrcoCjXQMAzJdV2ybZuyLKPj8UhxHFMcx1TXdS87jogU8QURPbYytwKBUQYOhwP5vk9xHFOWZXQ4HOh8PpNt2+T7vspMS5JE/ea6Lvm+T5ZlUVmWFEUROY6jstl4/0EQkO/7PblIkoSiKKIwDNV3z/OWZ5N2K0BEXZqmXdd1XVEUqmA8tun7oGh8GIa9fsIw7Gzb7tI07VYOQSC4V+CZ1v9831f75HneEVHXNE3XdV13Pp87IuqKohj0l6ZpZ1nWqDzleT7YDtkwbQ+CQH2vqqojoq6qqiWn9vbqOXsURRTH8ex+PCeXv6XEXBc8RjRNQ13XDf7yPB9tg+ebP9NlWVJZloqfEajrmsqypOPxqKwAk8xgaoxpMrbzXHZ8XkpkcRUtFebcQRDQ8XiUJ0TwfJxYf/VXZEoE/bu/+zv6n//5n56QRVFEvu8PhI2nqFqW1UtBTZJE+b0cxzEqQ0wDuLlveimsxVVz9iRJ1BxdIHhO+L//+7/ZfWzbpjRNKYoiyrJsMOe2LEu9ME6nEx0OB+XD4hYC5vr6nJvvEwQBbTabq2ioBi+ytQ2SJOk5IJZcGN1kN73NBILHAHjL9b/D4dDbLwgCZfLDwWx6pqGRQQet9zEnxNwhrssS2i6VxavM+CVzdX5CSZKQZVnkOA7VdT2YxwgEj2nOvlTp2bZNlmWpz67rqjk5BBAm+9hvsAo2mw3FcUy2bdPpdOqZ8WgfBIFayYI33nGc5Zx0a73xcRxPehTJ4GFM07RzHKcjos5xHOVphFdTIHhq8H2/s227I6LOdd3ufD6rVSrHcZRX33EcJQ9YhSKizrKszvd91Q6yVRRF57quam/bds/LH8dxZ9u2ao8VgSXeeKGlEgheBoSWSiB4KRBhFwhE2AUCwYsVdr4skSTJ4Ptut+sF/2+3217buq5VO76EwPvZbrdqX6IPHkt9Gz6jf3zm+/DtOCaWMfCd99G27aC9QHAL1HWtklcQkHY4HNTznmVZL5lMzx3BvlgCzLJMPe+8dvss1nrjuWeQf2+apquqqmuaRm3n3WMbvPLcq4/f0Abfz+dzL1YZx9L719sB2B7HcS9mH2Pgffi+PxrfLBDMAXke/A+ectu2uziOVSw796Dned6LnYf88Hh313XVs9s0TWdZlpIXy7KWeuTXx8Z7ntd7oyAdD/G82+22F1GENxK0Z13X5LruIMjAVNXieDzOriHCkuBvQVP6INYsL5eLsiqgxcuyFI0uuDfAokTQDbdQD4eDiltBCmwQBIOS6FEUqRRzlHJGOefFz+41mh2ZPCZNiLeXntGGbZZl9bKGkDGka2jXdTvXddW2MAx7b80pzY4+odFd1+2CIFDb8BntsJYpml1wH5odzz3W2PkzVlVVZ9v2QH6w/o7nG2vskLsxa/vmWW8mLazXjDYl1SP/HaGHp9OJyrI0hhnWdd3Lc4/jWGUgXTM+27bJcRyKomgQy2zKKRYIbgXbtqlpGgrDUEWS8rl227YDSxfy07ZtT5bwbCOrDv3dXLPz+TPX7tCY+B6GYVdVVW8ugt94NFEQBJ1lWWo+gjbQ/nybPg6+nbfDePgYfN/v4jhWY8Q8CN/xBka/AsEtAQsTz3rTNErLI3fddV21TxiG3fl87mzb7s7ns/IxoT1kj8uORNAJBAJAIugEgpcCEXaBQISdjE44LKXtdrt7HdjlcqH9fq++7/d7tWQGVk+deZOzck4FGyRJ0uubBy1gGQMMoXCcPOaAGyzL4L7ozlH9fIk+LGuiDdiGEGSE7ZxJWPAMsHbpbUVK3Z0ABwUn28NyhOkzHH5z4MttWBYBmSCCeHhgEJb/+FgeE+Ds4UEaJlJCvo/exrZttU0clM8Wy5feoC34spbOZw0NyS2B3W5Hl8vFuJ2IVIjtZrMxsnmMLWXoqOt6lqerbVs6Ho+9Jb2yLCkIAtVv27aKSQfMIEvJNT8FLMvqBVZwcgRocH3saIMAI24JLF7GETxfM75t24GQBUHQK/igs3NkWaYeKtN2IqLz+Uxd11FRFKOk+TpMa/NLqa7SNO2tqdd13WuHz1j7hCDdgvDvvpDnuZragHMcL2DHcYxjD8OQdrsd7XY7CsNQreciAlGPzxa8IDNeN6v1NXBia+8wi0lbk9e3T/WPKDj+x1k9dPOem/ZrzkVvh+9Y+3QcpwuCQK3LP0bYtt3led7lea4+83PUry0iGIui6OUNcDPe9/0B37/gaZvxi4Ud81hToE0cx53v+12apioUFXNHPEim7UhK4RQ8S+bsJmHH3HqtsPu+32uH+Suf7/q+PygM8FhwPp97BQzgZ8A15n8QZNd1e21831cvtqmXu+CFzNnHwmBBgoegfBDvoTwOnwLo22HeN01D5/N50TiyLDOapY7jXOU9dl1XTUUwf8W5RlFEaZpS27YqpHZNba2HmrPrab2WZVGapiq8GGWJMM3CnF2fotV1rbaPXWfBC/HGQ7txLcw1fhAEXRzHPSJJIhrd3jSNCgWkj+R8XLPw747jKE1LI6V5EHJIWgkqkzbkfSO9lYfLwjPP0xAfq6aDKY77ok9ncL64V6br3jRN7/66riu68Jlp9juHy9Z1TcfjcXlxuTuuvXue17MCTNsEAsEAX352l9ae51FZlg9aHcaU0WbaJhAI+pBEGIHghWh2iY0XCF4IRNgFAhF2gUAgwi4QCETYBQKBCLtAIPiE+IyIfi+XQSB49vjh/wGnWuqQDiIa/wAAAABJRU5ErkJggg==",
                      "mimeType": "image/png"
                    }
                  ],
                  "amount": 100,
                  "reason": "string"
                }
                """, paymentId);
    }

    public static String getCancelRequest(String invoiceId, String paymentId) {
        return String.format("""
                {
                  "cancelParams": [
                    {
                      "invoiceId": "%s",
                      "paymentId": "%s",
                      "cancelReason": "test endpoint"
                    }
                  ]
                }
                """, invoiceId, paymentId);
    }

    public static String getApproveRequest(String invoiceId, String paymentId, boolean skipHg) {
        return String.format("""
                {
                  "approveParams": [
                    {
                      "invoiceId": "%s",
                      "paymentId": "%s",
                      "skipCallHgForCreateAdjustment": %s
                    }
                  ]
                }
                """, invoiceId, paymentId, skipHg);
    }

    public static String getSetPendingForPoolingExpiredParamsRequest(String invoiceId, String paymentId) {
        return String.format("""
                  {
                    "setPendingForPoolingExpiredParams": [
                      {
                      "invoiceId": "%s",
                      "paymentId": "%s"
                      }
                    ]
                  }
                """, invoiceId, paymentId);
    }

    public static String getGetDisputeRequest(String invoiceId, String paymentId, boolean withAttachments) {
        return String.format("""
                  {
                    "disputeParams": [
                      {
                      "invoiceId": "%s",
                      "paymentId": "%s"
                      }
                    ],
                    "withAttachments": %s
                  }
                """, invoiceId, paymentId, withAttachments);
    }

    public static String getBindCreatedRequest(UUID disputeId, String providerDisputeId) {
        return String.format("""
                  {
                    "bindParams": [
                      {
                        "disputeId": "%s",
                        "providerDisputeId": "%s"
                      }
                    ]
                  }
                """, disputeId, providerDisputeId);
    }
}


FILE: ./src/test/java/dev/vality/disputes/util/TestUrlPaths.java
MD5:  7878ea76234405505224bfe07a9019ac
SHA1: e45c02b89881bea106de2186710d4febd7f6da34
package dev.vality.disputes.util;

import lombok.AccessLevel;
import lombok.NoArgsConstructor;

@NoArgsConstructor(access = AccessLevel.PRIVATE)
public class TestUrlPaths {

    public static final String S3_PATH = "/s3";
    public static final String MOCK_UPLOAD = "/mock/upload";
    public static final String MOCK_DOWNLOAD = "/mock/download";
    public static final String ADAPTER = "/adapter";
    public static final String NOTIFICATION_PATH = "/mock/v1/notify";

}


FILE: ./src/test/java/dev/vality/disputes/util/WiremockUtils.java
MD5:  ad293652f6601bfcbe1800842408c9d2
SHA1: c32a44315593e365a15875e39dd6161ee35dd5c4
package dev.vality.disputes.util;

import com.github.tomakehurst.wiremock.client.WireMock;

import java.util.Base64;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.stubFor;

@SuppressWarnings({"LineLength"})
public class WiremockUtils {

    public static void mockS3AttachmentUpload() {
        stubFor(WireMock.put(TestUrlPaths.S3_PATH + TestUrlPaths.MOCK_UPLOAD)
                .willReturn(aResponse()
                        .withStatus(200)
                        .withBody("")));
    }

    public static void mockS3AttachmentDownload() {
        stubFor(WireMock.get(TestUrlPaths.S3_PATH + TestUrlPaths.MOCK_DOWNLOAD)
                .willReturn(aResponse()
                        .withStatus(200)
                        .withBody(Base64.getDecoder().decode(
                                "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"))));
    }

    public static void mockNotificationSuccess() {
        stubFor(WireMock.post(TestUrlPaths.NOTIFICATION_PATH)
                .willReturn(aResponse()
                        .withStatus(200)
                        .withBody("")));
    }

    public static void mockNotification500() {
        stubFor(WireMock.post(TestUrlPaths.NOTIFICATION_PATH)
                .willReturn(aResponse()
                        .withStatus(500)));
    }
}


FILE: pom.xml
MD5:  13eabc5335e6da822bfb7269210b6dde
SHA1: 67c26a1d7f4c6bc2559d38f8ebc38c21df8e2d6f
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
<modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>dev.vality</groupId>
        <artifactId>service-parent-pom</artifactId>
        <version>3.0.9</version>
    </parent>

    <artifactId>disputes-api</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <name>disputes-api</name>
    <description>disputes api</description>

    <properties>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <project.reporting.outputEncoding>UTF-8</project.reporting.outputEncoding>
        <java.version>21</java.version>
        <maven.compiler.source>${java.version}</maven.compiler.source>
        <maven.compiler.target>${java.version}</maven.compiler.target>
        <server.port>8022</server.port>
        <management.port>8023</management.port>
        <exposed.ports>${server.port} ${management.port}</exposed.ports>
        <dockerfile.registry>${env.REGISTRY}</dockerfile.registry>
        <shared-resources.version>3.0.0</shared-resources.version>
        <db.name>disputes</db.name>
        <db.port>5432</db.port>
        <db.url>jdbc:postgresql://localhost:${db.port}/${db.name}</db.url>
        <db.user>postgres</db.user>
        <db.password>postgres</db.password>
        <db.schema>dspt</db.schema>
    </properties>

    <dependencies>
        <!--vality-->
        <dependency>
            <groupId>dev.vality</groupId>
            <artifactId>swag-disputes</artifactId>
            <version>1.19-8c4c6d9-server</version>
        </dependency>
        <dependency>
            <groupId>dev.vality</groupId>
            <artifactId>disputes-proto</artifactId>
            <version>1.47-264d870</version>
        </dependency>
        <dependency>
            <groupId>dev.vality</groupId>
            <artifactId>bouncer-proto</artifactId>
            <version>1.56-07dcc7b</version>
        </dependency>
        <dependency>
            <groupId>dev.vality.geck</groupId>
            <artifactId>serializer</artifactId>
            <version>1.0.2</version>
        </dependency>
        <dependency>
            <groupId>dev.vality</groupId>
            <artifactId>damsel</artifactId>
            <version>1.651-24932cd</version>
        </dependency>
        <dependency>
            <groupId>dev.vality</groupId>
            <artifactId>token-keeper-proto</artifactId>
            <version>1.37-be1f603</version>
        </dependency>
        <dependency>
            <groupId>dev.vality</groupId>
            <artifactId>file-storage-proto</artifactId>
            <version>1.49-f01d2d9</version>
        </dependency>
        <dependency>
            <groupId>dev.vality</groupId>
            <artifactId>db-common-lib</artifactId>
        </dependency>
        <dependency>
            <groupId>dev.vality</groupId>
            <artifactId>msgpack-proto</artifactId>
            <version>1.17-7481bb4</version>
        </dependency>
        <dependency>
            <groupId>dev.vality</groupId>
            <artifactId>adapter-flow-lib</artifactId>
            <version>1.0.1</version>
        </dependency>

        <!--spring-->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-jdbc</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-cache</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
            <exclusions>
                <exclusion>
                    <groupId>org.hibernate</groupId>
                    <artifactId>hibernate-validator</artifactId>
                </exclusion>
            </exclusions>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-configuration-processor</artifactId>
            <optional>true</optional>
        </dependency>

        <!--third party-->
        <dependency>
            <groupId>org.flywaydb</groupId>
            <artifactId>flyway-core</artifactId>
        </dependency>
        <dependency>
            <groupId>org.flywaydb</groupId>
            <artifactId>flyway-database-postgresql</artifactId>
        </dependency>
        <dependency>
            <groupId>org.jooq</groupId>
            <artifactId>jooq</artifactId>
        </dependency>
        <dependency>
            <groupId>com.zaxxer</groupId>
            <artifactId>HikariCP</artifactId>
        </dependency>
        <dependency>
            <groupId>org.postgresql</groupId>
            <artifactId>postgresql</artifactId>
        </dependency>
        <dependency>
            <groupId>jakarta.servlet</groupId>
            <artifactId>jakarta.servlet-api</artifactId>
            <version>6.1.0</version>
            <scope>provided</scope>
        </dependency>
        <dependency>
            <groupId>jakarta.inject</groupId>
            <artifactId>jakarta.inject-api</artifactId>
            <version>2.0.1</version>
            <scope>provided</scope>
        </dependency>
        <dependency>
            <groupId>com.google.code.findbugs</groupId>
            <artifactId>jsr305</artifactId>
            <version>3.0.2</version>
            <scope>provided</scope>
        </dependency>
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-databind</artifactId>
        </dependency>
        <dependency>
            <groupId>com.fasterxml.jackson.datatype</groupId>
            <artifactId>jackson-datatype-jdk8</artifactId>
        </dependency>
        <dependency>
            <groupId>org.openapitools</groupId>
            <artifactId>jackson-databind-nullable</artifactId>
            <version>0.2.6</version>
            <scope>provided</scope>
        </dependency>
        <dependency>
            <groupId>com.github.ben-manes.caffeine</groupId>
            <artifactId>caffeine</artifactId>
        </dependency>
        <dependency>
            <groupId>commons-io</groupId>
            <artifactId>commons-io</artifactId>
            <version>2.18.0</version>
        </dependency>
        <dependency>
            <groupId>com.google.guava</groupId>
            <artifactId>guava</artifactId>
            <version>33.4.0-jre</version>
        </dependency>
        <dependency>
            <groupId>io.opentelemetry</groupId>
            <artifactId>opentelemetry-semconv</artifactId>
            <version>1.29.0-alpha</version>
        </dependency>

        <!--test-->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.wiremock.integrations</groupId>
            <artifactId>wiremock-spring-boot</artifactId>
            <version>3.8.2</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>dev.vality</groupId>
            <artifactId>testcontainers-annotations</artifactId>
            <version>2.0.4</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>io.zonky.test</groupId>
            <artifactId>embedded-postgres</artifactId>
            <version>2.1.0</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>io.zonky.test.postgres</groupId>
            <artifactId>embedded-postgres-binaries-darwin-amd64</artifactId>
            <version>17.4.0</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>io.zonky.test</groupId>
            <artifactId>embedded-database-spring-test</artifactId>
            <version>2.6.0</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <sourceDirectory>${project.basedir}/src/main/java</sourceDirectory>
        <testSourceDirectory>${project.basedir}/src/test/java</testSourceDirectory>
        <resources>
            <resource>
                <directory>${project.build.directory}/maven-shared-archive-resources</directory>
                <targetPath>${project.build.directory}</targetPath>
                <includes>
                    <include>Dockerfile</include>
                </includes>
                <filtering>true</filtering>
            </resource>
            <resource>
                <directory>${project.build.directory}/maven-shared-archive-resources</directory>
                <filtering>true</filtering>
                <excludes>
                    <exclude>Dockerfile</exclude>
                </excludes>
            </resource>
            <resource>
                <directory>src/main/resources</directory>
                <filtering>true</filtering>
            </resource>
        </resources>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-remote-resources-plugin</artifactId>
                <version>3.3.0</version>
                <dependencies>
                    <dependency>
                        <groupId>org.apache.maven.shared</groupId>
                        <artifactId>maven-filtering</artifactId>
                        <version>3.4.0</version>
                    </dependency>
                </dependencies>
                <configuration>
                    <resourceBundles>
                        <resourceBundle>dev.vality:shared-resources:${shared-resources.version}</resourceBundle>
                    </resourceBundles>
                    <attachToMain>false</attachToMain>
                    <attachToTest>false</attachToTest>
                </configuration>
                <executions>
                    <execution>
                        <goals>
                            <goal>process</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>org.flywaydb</groupId>
                <artifactId>flyway-maven-plugin</artifactId>
                <configuration>
                    <url>${db.url}</url>
                    <user>${db.user}</user>
                    <password>${db.password}</password>
                    <schemas>
                        <schema>${db.schema}</schema>
                    </schemas>
                    <locations>
                        <location>filesystem:${project.basedir}/src/main/resources/db/migration</location>
                    </locations>
                </configuration>
                <executions>
                    <execution>
                        <id>migrate</id>
                        <phase>generate-sources</phase>
                        <goals>
                            <goal>migrate</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>org.jooq</groupId>
                <artifactId>jooq-codegen-maven</artifactId>
                <configuration>
                    <jdbc>
                        <driver>org.postgresql.Driver</driver>
                        <url>${db.url}</url>
                        <user>${db.user}</user>
                        <password>${db.password}</password>
                    </jdbc>
                    <generator>
                        <generate>
                            <javaTimeTypes>true</javaTimeTypes>
                            <pojos>true</pojos>
                            <pojosEqualsAndHashCode>true</pojosEqualsAndHashCode>
                            <pojosToString>true</pojosToString>
                        </generate>
                        <database>
                            <name>org.jooq.meta.postgres.PostgresDatabase</name>
                            <includes>.*</includes>
                            <excludes>schema_version|flyway_schema_history</excludes>
                            <inputSchema>${db.schema}</inputSchema>
                        </database>
                        <target>
                            <packageName>dev.vality.disputes.domain</packageName>
                            <directory>target/generated-sources/jooq</directory>
                        </target>
                    </generator>
                </configuration>
                <executions>
                    <execution>
                        <id>gen-src</id>
                        <phase>generate-sources</phase>
                        <goals>
                            <goal>generate</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>dev.vality.maven.plugins</groupId>
                <artifactId>pg-embedded-plugin</artifactId>
                <version>2.0.0</version>
                <configuration>
                    <port>${db.port}</port>
                    <dbName>${db.name}</dbName>
                    <schemas>
                        <schema>${db.schema}</schema>
                    </schemas>
                </configuration>
                <executions>
                    <execution>
                        <id>PG_server_start</id>
                        <phase>initialize</phase>
                        <goals>
                            <goal>start</goal>
                        </goals>
                    </execution>
                    <execution>
                        <id>PG_server_stop</id>
                        <phase>compile</phase>
                        <goals>
                            <goal>stop</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>org.cyclonedx</groupId>
                <artifactId>cyclonedx-maven-plugin</artifactId>
                <executions>
                    <execution>
                        <phase>generate-resources</phase>
                        <goals>
                            <goal>makeAggregateBom</goal>
                        </goals>
                        <configuration>
                            <projectType>application</projectType>
                            <outputDirectory>${project.build.directory}</outputDirectory>
                            <outputFormat>json</outputFormat>
                            <outputName>bom</outputName>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>

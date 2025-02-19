// Copyright SIX DAY LLC. All rights reserved.

import Foundation
import UIKit
import Combine
import AlphaWalletFoundation

protocol AccountsCoordinatorDelegate: AnyObject {
    func didCancel(in coordinator: AccountsCoordinator)
    func didSelectAccount(account: Wallet, in coordinator: AccountsCoordinator)
    func didAddAccount(account: Wallet, in coordinator: AccountsCoordinator)
    func didDeleteAccount(account: Wallet, in coordinator: AccountsCoordinator)
    func didFinishBackup(account: AlphaWallet.Address, in coordinator: AccountsCoordinator)
}

struct AccountsCoordinatorViewModel {
    var configuration: Configuration
    var animatedPresentation: Bool = false

    enum Configuration {
        case changeWallets
        case summary

        var hidesBackButton: Bool {
            switch self {
            case .changeWallets:
                return false
            case .summary:
                return true
            }
        }

        var allowsAccountDeletion: Bool {
            return true
        }

        var title: String {
            switch self {
            case .changeWallets:
                return R.string.localizable.walletNavigationTitle()
            case .summary:
                return R.string.localizable.walletsNavigationTitle()
            }
        }
    }
}

class AccountsCoordinator: Coordinator {
    private let config: Config
    private let keystore: Keystore
    private let analytics: AnalyticsLogger
    private let walletBalanceService: WalletBalanceService
    private let blockiesGenerator: BlockiesGenerator
    private let domainResolutionService: DomainResolutionServiceType
    private let viewModel: AccountsCoordinatorViewModel
    private var cancelable = Set<AnyCancellable>()

    let navigationController: UINavigationController
    var coordinators: [Coordinator] = []

    lazy var accountsViewController: AccountsViewController = {
        let viewModel = AccountsViewModel(keystore: keystore, config: config, configuration: self.viewModel.configuration, analytics: analytics, walletBalanceService: walletBalanceService, blockiesGenerator: blockiesGenerator, domainResolutionService: domainResolutionService)
        viewModel.allowsAccountDeletion = self.viewModel.configuration.allowsAccountDeletion

        let controller = AccountsViewController(viewModel: viewModel)
        controller.navigationItem.hidesBackButton = self.viewModel.configuration.hidesBackButton
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem.addButton(self, selector: #selector(addWallet))
        controller.delegate = self
        controller.hidesBottomBarWhenPushed = true

        return controller
    }()

    weak var delegate: AccountsCoordinatorDelegate?

    init(
        config: Config,
        navigationController: UINavigationController,
        keystore: Keystore,
        analytics: AnalyticsLogger,
        viewModel: AccountsCoordinatorViewModel,
        walletBalanceService: WalletBalanceService,
        blockiesGenerator: BlockiesGenerator,
        domainResolutionService: DomainResolutionServiceType
    ) {
        self.config = config
        self.navigationController = navigationController
        self.keystore = keystore
        self.analytics = analytics
        self.viewModel = viewModel
        self.walletBalanceService = walletBalanceService
        self.blockiesGenerator = blockiesGenerator
        self.domainResolutionService = domainResolutionService
    }

    func start() {
        accountsViewController.navigationItem.largeTitleDisplayMode = .never
        navigationController.pushViewController(accountsViewController, animated: viewModel.animatedPresentation)
    }

    @objc private func addWallet() {
        guard let barButtonItem = accountsViewController.navigationItem.rightBarButtonItem else { return }
        UIAlertController.alert(title: nil,
                message: nil,
                alertButtonTitles: [
                    R.string.localizable.walletCreateButtonTitle(),
                    R.string.localizable.walletImportButtonTitle(),
                    R.string.localizable.walletWatchButtonTitle(),
                    R.string.localizable.cancel()
                ],
                alertButtonStyles: [
                    .default,
                    .default,
                    .default,
                    .cancel
                ],
                viewController: navigationController,
                style: .actionSheet(source: .barButtonItem(barButtonItem))) { [weak self] index in
                    guard let strongSelf = self else { return }
                    if index == 0 {
                        strongSelf.showCreateWallet()
                    } else if index == 1 {
                        strongSelf.showImportWallet()
                    } else if index == 2 {
                        strongSelf.showWatchWallet()
                    }
        }
	}

    private func importOrCreateWallet(entryPoint: WalletEntryPoint) {
        let coordinator = WalletCoordinator(config: config, keystore: keystore, analytics: analytics, domainResolutionService: domainResolutionService)
        if case .createInstantWallet = entryPoint {
            coordinator.navigationController = navigationController
        }
        coordinator.delegate = self
        addCoordinator(coordinator)
        let showUI = coordinator.start(entryPoint)
        if showUI {
            coordinator.navigationController.makePresentationFullScreenForiOS13Migration()
            navigationController.present(coordinator.navigationController, animated: true)
        }
    }

    private func showInfoSheet(for account: Wallet, sender: UIView) {
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.popoverPresentationController?.sourceView = sender

        switch account.type {
        case .real(let address):
            let actionTitle: String
            if account.origin == .hd {
                actionTitle = R.string.localizable.walletsBackupHdWalletAlertSheetTitle()
            } else {
                actionTitle = R.string.localizable.walletsBackupKeystoreWalletAlertSheetTitle()
            }
            let backupKeystoreAction = UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
                self?.startBackup(for: account)
            }
            controller.addAction(backupKeystoreAction)

            let renameAction = UIAlertAction(title: R.string.localizable.walletsNameRename(), style: .default) { [weak self] _ in
                self?.promptRenameWallet(account)
            }

            if Features.default.isAvailable(.isRenameWalletEnabledWhileLongPress) {
                controller.addAction(renameAction)
            }

            let copyAction = UIAlertAction(title: R.string.localizable.copyAddress(), style: .default) { _ in
                UIPasteboard.general.string = address.eip55String
            }
            controller.addAction(copyAction)

            let cancelAction = UIAlertAction(title: R.string.localizable.cancel(), style: .cancel) { _ in }

            controller.addAction(cancelAction)

            navigationController.present(controller, animated: true)
        case .watch:
            let renameAction = UIAlertAction(title: R.string.localizable.walletsNameRename(), style: .default) { [weak self] _ in
                self?.promptRenameWallet(account)
            }
            controller.addAction(renameAction)

            let copyAction = UIAlertAction(title: R.string.localizable.copyAddress(), style: .default) { [navigationController] _ in
                UIPasteboard.general.string = account.address.eip55String
                navigationController.view.showCopiedToClipboard(title: R.string.localizable.copiedToClipboard())
            }
            controller.addAction(copyAction)
            let cancelAction = UIAlertAction(title: R.string.localizable.cancel(), style: .cancel) { _ in }
            controller.addAction(cancelAction)

            navigationController.present(controller, animated: true)
        }
    }

    private func startBackup(for account: Wallet) {
        let coordinator = BackupCoordinator(navigationController: navigationController, keystore: keystore, account: account, analytics: analytics)
        coordinator.delegate = self
        coordinator.start()
        addCoordinator(coordinator)
    }

    private func promptRenameWallet(_ account: Wallet) {
        let viewModel = RenameWalletViewModel(account: account.address, analytics: analytics, domainResolutionService: domainResolutionService)
        let viewController = RenameWalletViewController(viewModel: viewModel)
        viewController.delegate = self
        viewController.navigationItem.largeTitleDisplayMode = .never
        viewController.hidesBottomBarWhenPushed = true

        navigationController.pushViewController(viewController, animated: true)
    }

    private func showCreateWallet() {
        importOrCreateWallet(entryPoint: .createInstantWallet)
    }

    private func showImportWallet() {
        importOrCreateWallet(entryPoint: .importWallet(params: nil))
    }

    private func showWatchWallet() {
        importOrCreateWallet(entryPoint: .watchWallet(address: nil))
    }
}

extension AccountsCoordinator: RenameWalletViewControllerDelegate {
    func didFinish(in viewController: RenameWalletViewController) {
        navigationController.popViewController(animated: true)
    }
}

extension AccountsCoordinator: AccountsViewControllerDelegate {
    func didClose(in viewController: AccountsViewController) {
        delegate?.didCancel(in: self)
    }

    func didSelectAccount(account: Wallet, in viewController: AccountsViewController) {
        delegate?.didSelectAccount(account: account, in: self)
    }

    func didDeleteAccount(account: Wallet, in viewController: AccountsViewController) {
        delegate?.didDeleteAccount(account: account, in: self)
    }

    func didSelectInfoForAccount(account: Wallet, sender: UIView, in viewController: AccountsViewController) {
        showInfoSheet(for: account, sender: sender)
    }
}

extension AccountsCoordinator: WalletCoordinatorDelegate {
    func didFinish(with account: Wallet, in coordinator: WalletCoordinator) {
        delegate?.didAddAccount(account: account, in: self)
        if let delegate = delegate {
            removeCoordinator(coordinator)
            delegate.didSelectAccount(account: account, in: self)
        } else {
            coordinator.navigationController.dismiss(animated: true)
            removeCoordinator(coordinator)
        }
    }

    func didFail(with error: Error, in coordinator: WalletCoordinator) {
        coordinator.navigationController.dismiss(animated: true)
        removeCoordinator(coordinator)
    }

    func didCancel(in coordinator: WalletCoordinator) {
        coordinator.navigationController.dismiss(animated: true)
        removeCoordinator(coordinator)
    }
}

extension AccountsCoordinator: BackupCoordinatorDelegate {

    func didCancel(coordinator: BackupCoordinator) {
        removeCoordinator(coordinator)
    }

    func didFinish(account: AlphaWallet.Address, in coordinator: BackupCoordinator) {
        delegate?.didFinishBackup(account: account, in: self)

        removeCoordinator(coordinator)
    }
}

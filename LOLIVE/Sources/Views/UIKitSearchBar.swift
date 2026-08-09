//
//  UIKitSearchBar.swift
//  LOLIVE
//
//  SwiftUI .searchable()이 iOS 26에서 큰 타이틀과 결합할 때 위쪽 여백이 커지는
//  문제(실측 확인, 줄일 방법 없음)를 피하려고, 진짜 UIKit UISearchController를
//  직접 붙이는 브릿지. 앱스토어 등 1st-party 앱들이 쓰는 표준 방식과 동일
//  (navigationItem.searchController + hidesSearchBarWhenScrolling = false).
//

import SwiftUI
import UIKit

final class SearchHostingController<Content: View>: UIViewController {
    let searchController: UISearchController
    let contentViewController: UIHostingController<Content>

    init(searchController: UISearchController, content: Content) {
        self.contentViewController = UIHostingController(rootView: content)
        self.searchController = searchController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(contentViewController)
        view.addSubview(contentViewController.view)
        contentViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        contentViewController.didMove(toParent: self)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        guard let parent, parent.navigationItem.searchController == nil else { return }
        parent.navigationItem.searchController = searchController
        parent.navigationItem.hidesSearchBarWhenScrolling = false
    }
}

struct UIKitSearchBar<Content: View>: UIViewControllerRepresentable {
    @Binding var text: String
    var placeholder: String
    @ViewBuilder var content: () -> Content

    final class Coordinator: NSObject, UISearchResultsUpdating {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }
        func updateSearchResults(for searchController: UISearchController) {
            let newValue = searchController.searchBar.text ?? ""
            if text != newValue { text = newValue }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIViewController(context: Context) -> SearchHostingController<Content> {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = context.coordinator
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = placeholder
        searchController.searchBar.autocapitalizationType = .none
        return SearchHostingController(searchController: searchController, content: content())
    }

    func updateUIViewController(_ uiViewController: SearchHostingController<Content>, context: Context) {
        uiViewController.contentViewController.rootView = content()
        uiViewController.searchController.searchBar.placeholder = placeholder
    }
}

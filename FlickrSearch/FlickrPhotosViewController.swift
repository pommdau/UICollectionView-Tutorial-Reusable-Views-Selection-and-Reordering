import UIKit

final class FlickrPhotosViewController: UICollectionViewController {
  // MARK: - Properties
  private let reuseIdentifier = "FlickrCell"
  private let sectionInsets   = UIEdgeInsets(top: 50.0,
                                             left: 20.0,
                                             bottom: 50.0,
                                             right: 20.0)
  private var searches: [FlickrSearchResults] = []  // 各検索結果を保存する
  private let flickr                          = Flickr()  // Flickr検索用
  private let itemsPerRow: CGFloat            = 3
  
  // selectedPhotos keeps track of all currently selected photos while in sharing mode.
  private var selectedPhotos: [FlickrPhoto] = []
  // shareTextLabel gives the user feedback about how many photos are currently selected.
  private let shareLabel = UILabel()
  
  // 現在選択している写真の情報（大きく表示される）
  var largePhotoIndexPath: IndexPath? {
    didSet {
      var indexPaths: [IndexPath] = []
      if let largePhotoIndexPath = largePhotoIndexPath {
        indexPaths.append(largePhotoIndexPath)  // new value
      }

      if let oldValue = oldValue {
        indexPaths.append(oldValue)
      }
      
      // collectionViewのアップデート
      collectionView.performBatchUpdates({
        self.collectionView.reloadItems(at: indexPaths)
      }) { _ in
        // 配置完了後に選択したセルまでスクロールさせ、画面の中央とする
        if let largePhotoIndexPath = self.largePhotoIndexPath {
          self.collectionView.scrollToItem(at: largePhotoIndexPath,
                                           at: .centeredVertically,
                                           animated: true)
        }
      }
    }
  }
  
  // It’s responsible for tracking and updating when this view controller enters and leaves sharing mode.
  var sharing: Bool = false {
    didSet {
      collectionView.allowsMultipleSelection = sharing

      // 選択状態をリセット
      collectionView.selectItem(at: nil, animated: true, scrollPosition: [])
      selectedPhotos.removeAll()
      
      guard let shareButton = self.navigationItem.rightBarButtonItems?.first else {
        return
      }

      // shareingが有効になっていない場合
      guard sharing else {
        navigationItem.setRightBarButton(shareButton, animated: true)
        return
      }

      if largePhotoIndexPath != nil {
        largePhotoIndexPath = nil
      }

      updateSharedPhotoCountLabel()

      
      let sharingItem = UIBarButtonItem(customView: shareLabel)
      let items: [UIBarButtonItem] = [
        shareButton,
        sharingItem
      ]

      navigationItem.setRightBarButtonItems(items, animated: true)
    }
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // ドラッグを有効にするための設定
    collectionView.dragInteractionEnabled = true
    collectionView.dragDelegate = self
  }
  
  
  // MARK:- Actions
  @IBAction func share(_ sender: UIBarButtonItem) {
    guard !searches.isEmpty else {
        return
    }

    guard !selectedPhotos.isEmpty else {
      sharing.toggle()
      return
    }

    guard sharing else {
      return
    }
    
    // サムネイルの画像のリストを作成する
    let images: [UIImage] = selectedPhotos.compactMap { photo in
      if let thumbnail = photo.thumbnail {
        return thumbnail
      }

      return nil
    }

    guard !images.isEmpty else {
      return  // 選択された画像がなければ何もしない
    }
    
    let shareController = UIActivityViewController(activityItems: images,
                                                   applicationActivities: nil)
    shareController.completionWithItemsHandler = { _, _, _, _ in
      self.sharing = false
      self.selectedPhotos.removeAll()
      self.updateSharedPhotoCountLabel()
    }

    shareController.popoverPresentationController?.barButtonItem = sender
    shareController.popoverPresentationController?.permittedArrowDirections = .any
    present(shareController, animated: true, completion: nil)
  }
}


// MARK:- Private
private extension FlickrPhotosViewController {
  // indexを指定して画像オブジェクトを取得するための関数
  func photo(for indexPath: IndexPath) -> FlickrPhoto {
    return searches[indexPath.section].searchResults[indexPath.row]
  }
  
  // 大きい画像をダウンロードするためのメソッド
  func performLargeImageFetch(for indexPath: IndexPath, flickrPhoto: FlickrPhoto) {
    // cellの型を確認
    guard let cell = collectionView.cellForItem(at: indexPath) as? FlickrPhotoCell else {
      return
    }

    // ネットワークの状態を可視化する
    cell.activityIndicator.startAnimating()

    flickrPhoto.loadLargeImage { [weak self] result in
      // weakでselfをcaptureしているので開放されていないかを確認する
      guard let self = self else {
        return
      }

      switch result {
      case .results(let photo):
        if indexPath == self.largePhotoIndexPath {
          cell.imageView.image = photo.largeImage
        }
      case .error(_):
        return
      }
    }
  }
  
  
  func updateSharedPhotoCountLabel() {
    if sharing {
      shareLabel.text = "\(selectedPhotos.count) photos selected"
    } else {
      shareLabel.text = ""
    }

    shareLabel.textColor = themeColor

    UIView.animate(withDuration: 0.3) {
      self.shareLabel.sizeToFit()
    }
  }

  
}


// MARK: - Text Field Delegate
extension FlickrPhotosViewController : UITextFieldDelegate {
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    // 1
    let activityIndicator = UIActivityIndicatorView(style: .gray)
    textField.addSubview(activityIndicator)
    activityIndicator.frame = textField.bounds
    activityIndicator.startAnimating()
    
    flickr.searchFlickr(for: textField.text!) { searchResults in
      // 検索が完了した後の処理
      activityIndicator.removeFromSuperview()
      
      switch searchResults {
      case .error(let error) :
        print("Error Searching: \(error)")
      case .results(let results):
        print("Found \(results.searchResults.count) matching \(results.searchTerm)")
        self.searches.insert(results, at: 0)
        // 4
        self.collectionView?.reloadData()
      }
    }
    
    textField.text = nil
    textField.resignFirstResponder()
    return true
  }
}


// MARK: - UICollectionViewDataSource
extension FlickrPhotosViewController {
  //1
  override func numberOfSections(in collectionView: UICollectionView) -> Int {
    return searches.count
  }
  
  //2
  override func collectionView(_ collectionView: UICollectionView,
                               numberOfItemsInSection section: Int) -> Int {
    return searches[section].searchResults.count
  }
  
  //3
  override func collectionView(_ collectionView: UICollectionView,
                               cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    
    guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier,
                                                        for: indexPath) as? FlickrPhotoCell else {
                                                          preconditionFailure("Invalid cell type")
    }
    
    let flickrPhoto = photo(for: indexPath)
    cell.activityIndicator.stopAnimating()  // すでに実行中の場合に備えて停止させる
    
    // 現在の対象のセルがlargeでない場合は小さい画像をセット
    guard indexPath == largePhotoIndexPath else {
      cell.imageView.image = flickrPhoto.thumbnail
      return cell
    }
    
    guard flickrPhoto.largeImage == nil else {
      // largeImageがすでに読み込まれている場合？（一度tap済み？）
      cell.imageView.image = flickrPhoto.largeImage
      return cell
    }
    
    // 以後Large画像を表示した。ますはthumbnail画像をセットしておく。
    cell.imageView.image = flickrPhoto.thumbnail
    
    // 5
    performLargeImageFetch(for: indexPath, flickrPhoto: flickrPhoto)

    return cell
  }
  
  // ヘッダのViewを返す
  // Headerを有効にしたことで、UICollectionViewFlowLayoutより呼び出される
  override func collectionView(_ collectionView: UICollectionView,
                               viewForSupplementaryElementOfKind kind: String,
                               at indexPath: IndexPath) -> UICollectionReusableView {
    switch kind {
    case UICollectionView.elementKindSectionHeader:
      guard
        let headerView = collectionView.dequeueReusableSupplementaryView(
          ofKind: kind,
          withReuseIdentifier: "\(FlickrPhotoHeaderView.self)",
          for: indexPath) as? FlickrPhotoHeaderView
        else {
          fatalError("Invalid view type")
      }
      let searchTerm = searches[indexPath.section].searchTerm
      headerView.label.text = searchTerm
      return headerView
      
    default:
      assert(false, "Invalid element type")
    }
  }
}


// MARK: - Collection View Flow Layout Delegate
extension FlickrPhotosViewController : UICollectionViewDelegateFlowLayout {
  // セルのサイズに関するレイアウトを決定する
  func collectionView(_ collectionView: UICollectionView,
                      layout collectionViewLayout: UICollectionViewLayout,
                      sizeForItemAt indexPath: IndexPath) -> CGSize {

    if indexPath == largePhotoIndexPath {
      // アスペクト比を保って、CollectionViewに沿う大きさにする
      let flickrPhoto = photo(for: indexPath)
      var size        = collectionView.bounds.size
      size.height -= (sectionInsets.top  + sectionInsets.bottom)
      size.width  -= (sectionInsets.left + sectionInsets.right)
      return flickrPhoto.sizeToFillWidth(of: size)
    }
    
    let paddingSpace   = sectionInsets.left * (itemsPerRow + 1)
    let availableWidth = view.frame.width - paddingSpace
    let widthPerItem   = availableWidth / itemsPerRow
    
    return CGSize(width: widthPerItem, height: widthPerItem)
  }
  
  // セル同士の、上下左右の余白を設定する
  func collectionView(_ collectionView: UICollectionView,
                      layout collectionViewLayout: UICollectionViewLayout,
                      insetForSectionAt section: Int) -> UIEdgeInsets {
    return sectionInsets
  }
  
  // Row同士の余白を設定する
  func collectionView(_ collectionView: UICollectionView,
                      layout collectionViewLayout: UICollectionViewLayout,
                      minimumLineSpacingForSectionAt section: Int) -> CGFloat {
    return sectionInsets.left
  }
}

// MARK: - UICollectionViewDelegate
extension FlickrPhotosViewController {
  // セルを選択したときに呼ばれるメソッド
  override func collectionView(_ collectionView: UICollectionView,
                               shouldSelectItemAt indexPath: IndexPath) -> Bool {
    guard !sharing else {
      return true  // SharingModeのときのみ選択は有効
    }
    
    if largePhotoIndexPath == indexPath {
      largePhotoIndexPath = nil  // すでに選択している場合は、画像を元の大きさにする
    } else {
      largePhotoIndexPath = indexPath
    }

    return false
  }
  
  override func collectionView(_ collectionView: UICollectionView,
                               didSelectItemAt indexPath: IndexPath) {
    guard sharing else {
      return
    }

    let flickrPhoto = photo(for: indexPath)
    selectedPhotos.append(flickrPhoto)
    updateSharedPhotoCountLabel()
  }

  
  override func collectionView(_ collectionView: UICollectionView,
                               didDeselectItemAt indexPath: IndexPath) {
    guard sharing else {
      return
    }
    
    // sharingモードのとき、選択解除
    let flickrPhoto = photo(for: indexPath)
    if let index = selectedPhotos.firstIndex(of: flickrPhoto) {
      selectedPhotos.remove(at: index)
      updateSharedPhotoCountLabel()
    }
  }

}


// MARK: - UICollectionViewDragDelegate
extension FlickrPhotosViewController: UICollectionViewDragDelegate {
  /// Provides the initial set of items (if any) to drag.
  func collectionView(_ collectionView: UICollectionView,
                      itemsForBeginning session: UIDragSession,
                      at indexPath: IndexPath) -> [UIDragItem] {
    let flickrPhoto = photo(for: indexPath)
    guard let thumbnail = flickrPhoto.thumbnail else {
      return []
    }
    let item = NSItemProvider(object: thumbnail)
    let dragItem = UIDragItem(itemProvider: item)
    return [dragItem]
  }
}

import UIKit
import Photos
import FDTake
import IIDelayedAction
import JGProgressHUD

let IS_IPAD = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.pad
let IS_IPHONE = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.phone
let SCREEN_WIDTH = UIScreen.main.bounds.size.width
let SCREEN_HEIGHT = UIScreen.main.bounds.size.height
let IS_LARGE_SCREEN = IS_IPHONE && max(SCREEN_WIDTH, SCREEN_HEIGHT) >= 736.0

final class ViewController: UIViewController {
	var sourceImage: UIImage? {
		didSet {
			self.imageModel = ImageModel(image: self.sourceImage!)
		}
	}
	var delayedAction: IIDelayedAction?
	var blurAmount: Float = 0
	let stockImages = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: "Bundled Photos")!
	lazy var randomImageIterator: AnyIterator<URL> = self.stockImages.uniqueRandomElement()
	
	var filterStack = Stack<FilterCategory>()
	var filterQueue = Queue<FilterCategory>()

	var imageModel: ImageModel?
	let pendingOperations = PendingOperations()
	
	
	lazy var imageView = with(UIImageView()) {
		$0.image = UIImage(color: .black, size: view.frame.size)
		$0.contentMode = .scaleAspectFill
		$0.isUserInteractionEnabled = true
		$0.clipsToBounds = false
		let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture))
		pinchGesture.scale = 1.0
		$0.addGestureRecognizer(pinchGesture)
		let longGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleShare))
		longGesture.numberOfTouchesRequired = 1
		$0.addGestureRecognizer(longGesture)
		
		let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipGesture))
		swipeRight.direction = .right
		$0.addGestureRecognizer(swipeRight)
		
		let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipGesture))
		swipeLeft.direction = .left
		$0.addGestureRecognizer(swipeLeft)
		
		$0.frame = view.bounds
	}

	lazy var slider = with(UISlider()) {
		let SLIDER_MARGIN: CGFloat = 120
		$0.frame = CGRect(x: 0, y: 0, width: view.frame.size.width - SLIDER_MARGIN, height: view.frame.size.height)
		$0.minimumValue = 0
		$0.maximumValue = 100
		$0.value = blurAmount
		$0.isContinuous = true
		$0.setThumbImage(UIImage(named: "SliderThumb")!, for: .normal)
		$0.autoresizingMask = [
			.flexibleWidth,
			.flexibleTopMargin,
			.flexibleBottomMargin,
			.flexibleLeftMargin,
			.flexibleRightMargin
		]
		$0.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	override var prefersStatusBarHidden: Bool {
		return true
	}

	override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
		if motion == .motionShake {
			randomImage()
		}
	}
	
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		
		// This is to ensure that it always ends up with the current blur amount when the slider stops
		// since we're using `DispatchQueue.global().async` the order of events aren't serial
		delayedAction = IIDelayedAction({}, withDelay: 0.2)
		delayedAction?.onMainThread = false
		view.addSubview(imageView)
		self.view.isUserInteractionEnabled = true

		let TOOLBAR_HEIGHT: CGFloat = 80 + window.safeAreaInsets.bottom
		let toolbar = UIToolbar(frame: CGRect(x: 0, y: view.frame.size.height - TOOLBAR_HEIGHT, width: view.frame.size.width, height: TOOLBAR_HEIGHT))
		toolbar.autoresizingMask = .flexibleWidth
		toolbar.alpha = 0.6
		toolbar.tintColor = #colorLiteral(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)

		// Remove background
		toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
		toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

		// Gradient background
		let GRADIENT_PADDING: CGFloat = 40
		let gradient = CAGradientLayer()
		gradient.frame = CGRect(x: 0, y: -GRADIENT_PADDING, width: toolbar.frame.size.width, height: toolbar.frame.size.height + GRADIENT_PADDING)
		gradient.colors = [
			UIColor.clear.cgColor,
			UIColor.black.withAlphaComponent(0.1).cgColor,
			UIColor.black.withAlphaComponent(0.3).cgColor,
			UIColor.black.withAlphaComponent(0.4).cgColor
		]
		toolbar.layer.addSublayer(gradient)

		toolbar.items = [
			UIBarButtonItem(image: UIImage(named: "PickButton")!, target: self, action: #selector(pickImage), width: 20),
			.flexibleSpace,
			UIBarButtonItem(customView: slider),
			.flexibleSpace,
			UIBarButtonItem(image: UIImage(named: "SaveButton")!, target: self, action: #selector(saveImage), width: 20)
		]
		view.addSubview(toolbar)

		// Important that this is here at the end for the fading to work
		randomImage()
		loadFilterCategory()
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		suspendAllOperations()
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		resumeAllOperations()
	}
	
	@objc
	func pickImage() {
		let fdTake = FDTakeController()
		fdTake.allowsVideo = false
		fdTake.didGetPhoto = { photo, _ in
			self.changeImage(photo)
			self.filterStack.clear()
			self.filterQueue.clear()
			self.loadFilterCategory()
		}
		fdTake.present()
	}

	func blurImage(_ blurAmount: Float) -> UIImage {
		return UIImageEffects.imageByApplyingBlur(
			to: filterStack.isEmpty ? sourceImage : imageModel?.image,
			withRadius: CGFloat(blurAmount * (IS_LARGE_SCREEN ? 0.8 : 1.2)),
			tintColor: UIColor(white: 1, alpha: CGFloat(max(0, min(0.25, blurAmount * 0.004)))),
			saturationDeltaFactor: CGFloat(max(1, min(2.8, blurAmount * (IS_IPAD ? 0.035 : 0.045)))),
			maskImage: nil
		)
	}

	@objc
	func updateImage() {
		DispatchQueue.global(qos: .userInteractive).async {
			let tmp = self.blurImage(self.blurAmount)
			DispatchQueue.main.async {
				self.imageView.image = tmp
			}
		}
	}

	func updateImageDebounced() {
		performSelector(inBackground: #selector(updateImage), with: IS_IPAD ? 0.1 : 0.06)
	}

	@objc
	func sliderChanged(_ sender: UISlider) {
		blurAmount = sender.value
		updateImageDebounced()
		delayedAction?.action {
			self.updateImage()
		}
	}

	@objc
	func saveImage(_ button: UIBarButtonItem) {
		button.isEnabled = false

		PHPhotoLibrary.save(image: imageView.image!, toAlbum: "Blear") { result in
			button.isEnabled = true

			let HUD = JGProgressHUD(style: .dark)
			HUD.indicatorView = JGProgressHUDSuccessIndicatorView()
			HUD.animation = JGProgressHUDFadeZoomAnimation()
			HUD.vibrancyEnabled = true
			HUD.contentInsets = UIEdgeInsets(all: 30)

			if case .failure(let error) = result {
				HUD.indicatorView = JGProgressHUDErrorIndicatorView()
				HUD.textLabel.text = error.localizedDescription
				HUD.show(in: self.view)
				HUD.dismiss(afterDelay: 3)
				return
			}

			//HUD.indicatorView = JGProgressHUDImageIndicatorView(image: #imageLiteral(resourceName: "HudSaved"))
			HUD.show(in: self.view)
			HUD.dismiss(afterDelay: 0.8)

			// Only on first save
			if UserDefaults.standard.isFirstLaunch {
				delay(seconds: 1) {
					let alert = UIAlertController(
						title: "Changing Wallpaper",
						message: "In the Photos app go to the wallpaper you just saved, tap the action button on the bottom left and choose 'Use as Wallpaper'.",
						preferredStyle: .alert
					)
					alert.addAction(UIAlertAction(title: "OK", style: .default))
					self.present(alert, animated: true)
				}
			}
		}
	}

	/// TODO: Improve this method
	func changeImage(_ image: UIImage) {
		let tmp = NSKeyedUnarchiver.unarchiveObject(with: NSKeyedArchiver.archivedData(withRootObject: imageView)) as! UIImageView
		view.insertSubview(tmp, aboveSubview: imageView)
		imageView.image = image
		sourceImage = imageView.toImage()
		updateImageDebounced()

		// The delay here is important so it has time to blur the image before we start fading
		UIView.animate(
			withDuration: 0.6,
			delay: 0.3,
			options: .curveEaseInOut,
			animations: {
				tmp.alpha = 0
			}, completion: { _ in
				tmp.removeFromSuperview()
			}
		)
	}

	func randomImage() {
		changeImage(UIImage(contentsOf: randomImageIterator.next()!)!)
	}
	
}


extension ViewController {

	fileprivate func loadFilterCategory(){
		FilterCategory.allCases.forEach {
			self.filterQueue.enqueue($0)
		}
	}
	
	@objc fileprivate func handleSwipGesture(_ sender:UISwipeGestureRecognizer){
		switch sender.direction {
		case .right:
			self.applyFilterOnRightSwipe()
			
		case .left:
			self.applyFilterOnLeftSwipe()
			
		default:
			print("other swipe")
		}
	}
	
	@objc fileprivate func handleShare(_ sender:UILongPressGestureRecognizer) {
		if let image = self.imageView.image {
			let vc = UIActivityViewController(activityItems: [image], applicationActivities: [])
			self.present(vc, animated: true)
		}
	}
	
	@objc fileprivate func handlePinchGesture(sender: UIPinchGestureRecognizer) {
		guard let transformedView = (sender.view?.transform.scaledBy(x: sender.scale, y: sender.scale)) else {
			return
		}
		sender.view?.transform = transformedView
		sender.scale = 1.0
	}
	
	func startOperations(for imageModel: ImageModel,filterCategory: FilterCategory, at index: Int) {
		switch (imageModel.state) {
		case .new:
			startFiltration(for: imageModel, filterCategory: filterCategory, at: index)
		case .filtered:
			self.updateImage()
		default:
			NSLog("do nothing")
		}
	}
	
	func startFiltration(for imageModel: ImageModel, filterCategory: FilterCategory, at index: Int) {
		guard pendingOperations.filtrationsInProgress[index] == nil else {
			return
		}
		
		let filterer = FilterManager(imageModel, filterCategory: filterCategory)
		filterer.completionBlock = {
			if filterer.isCancelled {
				return
			}
			DispatchQueue.main.async {
				self.pendingOperations.filtrationsInProgress.removeValue(forKey: index)
				imageModel.state = .filtered
				self.startOperations(for: imageModel, filterCategory: filterCategory, at: index)
			}
		}
		
		pendingOperations.filtrationsInProgress[index] = filterer
		pendingOperations.filtrationQueue.addOperation(filterer)
	}

	func suspendAllOperations() {
		pendingOperations.filtrationQueue.isSuspended = true
	}
	
	func resumeAllOperations() {
		pendingOperations.filtrationQueue.isSuspended = false
	}
	
	func startFilteringImage(_ filterCategory: FilterCategory) {
		let allPendingOperations = Set(pendingOperations.filtrationsInProgress.keys)
		let toBeCancelled = allPendingOperations
		for indexPath in toBeCancelled {
			if let pendingFiltration = pendingOperations.filtrationsInProgress[indexPath] {
				pendingFiltration.cancel()
			}
			
			pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
		}
		
		
		guard let recordToProcess = self.imageModel else {return}
		recordToProcess.state = .new
		recordToProcess.image = self.sourceImage
		startOperations(for: recordToProcess, filterCategory: filterCategory, at: 0)

	}
}


extension ViewController {
	
	
	fileprivate func applyFilterOnRightSwipe() {
		print("left to right swipe")
		if let element = self.filterStack.pop() {
			self.startFilteringImage(element)
			self.filterQueue.enqueue(element)
		}

	}
	
	fileprivate func applyFilterOnLeftSwipe() {
		print("right to left swipe")
		if let element = filterQueue.dequeue() {
			self.startFilteringImage(element)
			self.filterStack.push(element)
		}
		
	}
	
}

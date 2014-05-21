//
//  ImportWalletViewController.m
//  AirBitz
//
//  Created by Adam Harris on 5/19/14.
//  Copyright (c) 2014 AirBitz. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "CommonTypes.h"
#import "ABC.h"
#import "ImportWalletViewController.h"
#import "ButtonSelectorView.h"
#import "FlashSelectView.h"
#import "StylizedTextField.h"
#import "Util.h"
#import "User.h"
#import "LatoLabel.h"
#import "ZBarSDK.h"

#define WALLET_BUTTON_WIDTH 150

#define SCANNER_DELAY_SECS  0

#define READER_VIEW_TAG     99999999

@interface ImportWalletViewController () <ButtonSelectorDelegate, UITextFieldDelegate, FlashSelectViewDelegate, ZBarReaderDelegate, ZBarReaderViewDelegate, UIAlertViewDelegate>
{
    ZBarReaderView          *_readerView;
    ZBarReaderController    *_readerPicker;
    NSTimer                 *_startScannerTimer;
    NSInteger               _selectedWallet;
    BOOL                    _bUsingImagePicker;
    BOOL                    _bShowingPassword;
}

@property (weak, nonatomic) IBOutlet UIView             *viewHeader;
@property (weak, nonatomic) IBOutlet UIView             *viewPassword;
@property (weak, nonatomic) IBOutlet StylizedTextField  *textPassword;
@property (weak, nonatomic) IBOutlet ButtonSelectorView *buttonSelector;
@property (weak, nonatomic) IBOutlet StylizedTextField  *textPrivateKey;
@property (weak, nonatomic) IBOutlet UIImageView        *scanFrame;
@property (weak, nonatomic) IBOutlet UIImageView        *imageFlashFrame;
@property (weak, nonatomic) IBOutlet FlashSelectView    *flashSelector;
@property (weak, nonatomic) IBOutlet UIView             *viewDisplay;
@property (weak, nonatomic) IBOutlet UIView             *viewTop;
@property (weak, nonatomic) IBOutlet UIView             *viewMiddle;
@property (weak, nonatomic) IBOutlet UIView             *viewBottom;
@property (weak, nonatomic) IBOutlet LatoLabel          *labelEnter;

@property (nonatomic, strong) NSArray  *arrayWalletUUIDs;
@property (nonatomic, copy)   NSString *strPassword;

@end

@implementation ImportWalletViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    _bUsingImagePicker = NO;
    _bShowingPassword = NO;

    self.flashSelector.delegate = self;
    self.textPrivateKey.delegate = self;

	self.buttonSelector.delegate = self;
	self.buttonSelector.textLabel.text = NSLocalizedString(@"Import Wallet:", nil);
    [self.buttonSelector setButtonWidth:WALLET_BUTTON_WIDTH];

    // get a callback when the private key changes
    [self.textPrivateKey addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    [self setWalletData];

    [self updateDisplayLayout];

    [self updateDisplay];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)viewWillAppear:(BOOL)animated
{
	//NSLog(@"Starting timer");

    if (_bUsingImagePicker == NO)
    {
        [self performSelector:@selector(startCameraScanner) withObject:nil afterDelay:SCANNER_DELAY_SECS];
        //_startScannerTimer = [NSTimer scheduledTimerWithTimeInterval:SCANNER_DELAY_SECS target:self selector:@selector(startCameraScanner:) userInfo:nil repeats:NO];

        [self.flashSelector selectItem:FLASH_ITEM_AUTO];
    }
}

-(void)viewWillDisappear:(BOOL)animated
{
	//NSLog(@"Invalidating timer");
	[_startScannerTimer invalidate];
	_startScannerTimer = nil;

	[self closeCameraScanner];
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

#pragma - Action Methods

- (IBAction)buttonBackTouched:(id)sender
{
    [self animatedExit];
}

- (IBAction)buttonCameraTouched:(id)sender
{
    [self showImageScanner];
}

- (IBAction)buttonInfoTouched:(id)sender
{
}

#pragma mark - Misc Methods

- (void)updateDisplay
{
    BOOL bHideEnter = YES;

    if ((![self.textPrivateKey isFirstResponder]) && ([self.textPrivateKey.text length] == 0))
    {
        bHideEnter = NO;
    }

    self.labelEnter.hidden = bHideEnter;

    self.viewDisplay.hidden = _bShowingPassword;
    self.viewPassword.hidden = !_bShowingPassword;

    // move the dislay and password views to correct y, just in case the xib moved them for editing
    CGRect frame = self.viewDisplay.frame;
    frame.origin.y = self.viewHeader.frame.origin.y + self.viewHeader.frame.size.height;
    frame.origin.x = 0;
    self.viewDisplay.frame = frame;
    frame = self.viewPassword.frame;
    frame.origin.y = self.viewHeader.frame.origin.y + self.viewHeader.frame.size.height;
    frame.origin.x = 0;
    self.viewPassword.frame = frame;
}

- (void)updateDisplayLayout
{
    // update for iPhone 4
    if (!IS_IPHONE5)
    {
        CGRect frame = self.viewTop.frame;
        frame.origin.y = 0;
        self.viewTop.frame = frame;

        frame = self.viewMiddle.frame;
        frame.origin.y = self.viewTop.frame.origin.y + self.viewTop.frame.size.height;
        self.viewMiddle.frame = frame;

        frame = self.viewBottom.frame;
        frame.origin.y = self.viewMiddle.frame.origin.y + self.viewMiddle.frame.size.height;
        frame.size.height = self.viewDisplay.frame.size.height - self.viewTop.frame.size.height - self.viewMiddle.frame.size.height;
        self.viewBottom.frame = frame;

        frame = self.scanFrame.frame;
        frame.origin.y = 0;
        frame.size.height = self.viewBottom.frame.size.height - self.imageFlashFrame.frame.size.height;
        frame.size.height -= 3; // some alpha at the top of the flash frame
        self.scanFrame.frame = frame;
    }
}

- (void)requestPassword
{
    _bShowingPassword = YES;
    [self updateDisplay];
    [self.textPassword becomeFirstResponder];
}

- (void)setWalletData
{
	tABC_WalletInfo **aWalletInfo = NULL;
    unsigned int nCount;
	tABC_Error Error;
    ABC_GetWallets([[User Singleton].name UTF8String], [[User Singleton].password UTF8String], &aWalletInfo, &nCount, &Error);
    [Util printABC_Error:&Error];

	if (nCount)
	{
		tABC_WalletInfo *info = aWalletInfo[0];

		[self.buttonSelector.button setTitle:[NSString stringWithUTF8String:info->szName] forState:UIControlStateNormal];
		self.buttonSelector.selectedItemIndex = 0;
        _selectedWallet = 0;
	}

    // assign list of wallets to buttonSelector
	NSMutableArray *walletsArray = [[NSMutableArray alloc] init];
    NSMutableArray *arrayWalletUUIDs = [[NSMutableArray alloc] init];

    for (int i = 0; i < nCount; i++)
    {
        tABC_WalletInfo *pInfo = aWalletInfo[i];
		[walletsArray addObject:[NSString stringWithUTF8String:pInfo->szName]];
        [arrayWalletUUIDs addObject:[NSString stringWithUTF8String:pInfo->szName]];
    }

	self.buttonSelector.arrayItemsToSelect = [walletsArray copy];
    self.arrayWalletUUIDs = arrayWalletUUIDs;

    ABC_FreeWalletInfoArray(aWalletInfo, nCount);
}

- (void)checkEnteredPassword
{
    self.strPassword = self.textPassword.text;

    // TODO: core needs to check if password is correct
    // self.strPassword
    // for now assume it is
    BOOL bPasswordValid = YES;

    if (bPasswordValid)
    {
        [self importWallet];
    }
    else
    {
        UIAlertView *alert = [[UIAlertView alloc]
                              initWithTitle:NSLocalizedString(@"Import Failed", nil)
                              message:NSLocalizedString(@"Invalid password", nil)
                              delegate:nil
                              cancelButtonTitle:@"OK"
                              otherButtonTitles:nil];
        [alert show];
        [self.textPassword becomeFirstResponder];
    }
}

- (void)importWallet
{
    // TODO: is here that the core needs to import the wallet given all the data:
    //strWalletUUID = [self.arrayWalletUUIDs objectAtIndex:_selectedWallet];
    //self.strPassword
    //self.strPrivateKey

    UIAlertView *alert = [[UIAlertView alloc]
                          initWithTitle:NSLocalizedString(@"Import Success", nil)
                          message:NSLocalizedString(@"The wallet was succesfully imported", nil)
                          delegate:self
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil];
    [alert show];
}

- (void)triggerImportStart
{
    self.strPassword = @"";

    // the private key should now have something in it
    // it is here that the private key info should be given to the core
    // the core can then determine whether a password is require
    // TODO: core needs to check self.textPrivate.text for password requirement

    // for now assume a password is needed
    BOOL bPasswordRequired = YES;
    if (bPasswordRequired)
    {
        [self requestPassword];
    }
    else
    {
        [self importWallet];
    }
}

- (void)processZBarResults:(ZBarSymbolSet *)syms
{
	for (ZBarSymbol *sym in syms)
	{
		NSString *strText = (NSString *)sym.data;

		//NSLog(@"text: %@", strText);

        self.textPrivateKey.text = strText;

		break; //just grab first one
	}

    [self updateDisplay];

    [self performSelector:@selector(triggerImportStart) withObject:nil afterDelay:0.0];
}


- (void)showImageScanner
{
    [self closeCameraScanner];

    _bUsingImagePicker = YES;

    _readerPicker = [ZBarReaderController new];
    _readerPicker.readerDelegate = self;
    if ([ZBarReaderController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary])
    {
        _readerPicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    }
    [_readerPicker.scanner setSymbology:ZBAR_I25 config:ZBAR_CFG_ENABLE to:0];
    _readerPicker.showsHelpOnFail = NO;

    [self presentViewController:_readerPicker animated:YES completion:nil];
    //[self presentModalViewController:_readerPicker animated: YES];
}

- (void)startCameraScanner
{
#if !TARGET_IPHONE_SIMULATOR
    // NSLog(@"Scanning...");

	_readerView = [ZBarReaderView new];
	[self.viewBottom insertSubview:_readerView belowSubview:self.scanFrame];
	_readerView.frame = self.scanFrame.frame;
	_readerView.readerDelegate = self;
	_readerView.tracksSymbols = NO;

	_readerView.tag = READER_VIEW_TAG;

	if (self.textPrivateKey.text.length)
	{
		_readerView.alpha = 0.0;
	}

	[_readerView start];
	[self flashItemSelected:FLASH_ITEM_AUTO];
#endif
}

- (void)closeCameraScanner
{
    if (_readerView)
    {
        [_readerView stop];
        [_readerView removeFromSuperview];
        _readerView = nil;
    }
}

- (void)animatedExit
{
	[UIView animateWithDuration:0.35
						  delay:0.0
						options:UIViewAnimationOptionCurveEaseInOut
					 animations:^
	 {
		 CGRect frame = self.view.frame;
		 frame.origin.x = frame.size.width;
		 self.view.frame = frame;
	 }
                     completion:^(BOOL finished)
	 {
		 [self exit];
	 }];
}

- (void)exit
{
	[self.delegate importWalletViewControllerDidFinish:self];
}

#pragma mark - ButtonSelectorView delegate

- (void)ButtonSelector:(ButtonSelectorView *)view selectedItem:(int)itemIndex
{
	//NSLog(@"Selected item %i", itemIndex);
    _selectedWallet = itemIndex;
}

- (void)ButtonSelectorWillShowTable:(ButtonSelectorView *)view
{
    [self.textPrivateKey resignFirstResponder];
}

#pragma mark - UITextField delegates

- (void)textFieldDidChange:(UITextField *)textField
{
    if (!_bShowingPassword)
    {
        [self updateDisplay];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	[textField resignFirstResponder];

    if (!_bShowingPassword)
    {
        [self updateDisplay];

        [self performSelector:@selector(triggerImportStart) withObject:nil afterDelay:0.0];
    }
    else
    {
        [self performSelector:@selector(checkEnteredPassword) withObject:nil afterDelay:0.0];
    }

	return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    if (!_bShowingPassword)
    {
        [_readerView stop];
        [self.buttonSelector close];

        [self updateDisplay];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if (!_bShowingPassword)
    {
        [self updateDisplay];
    }
}

#pragma mark - Flash Select Delegates

-(void)flashItemSelected:(tFlashItem)flashType
{
	//NSLog(@"Flash Item Selected: %i", flashType);
	AVCaptureDevice *device = _readerView.device;
	if (device)
	{
		switch (flashType)
		{
            case FLASH_ITEM_OFF:
                if ([device isTorchModeSupported:AVCaptureTorchModeOff])
                {
                    NSError *error = nil;
                    if ([device lockForConfiguration:&error])
                    {
                        device.torchMode = AVCaptureTorchModeOff;
                        [device unlockForConfiguration];
                    }
                }
                break;
            case FLASH_ITEM_ON:
                if ([device isTorchModeSupported:AVCaptureTorchModeOn])
                {
                    NSError *error = nil;
                    if ([device lockForConfiguration:&error])
                    {
                        device.torchMode = AVCaptureTorchModeOn;
                        [device unlockForConfiguration];
                    }
                }
                break;
            case FLASH_ITEM_AUTO:
                if ([device isTorchModeSupported:AVCaptureTorchModeAuto])
                {
                    NSError *error = nil;
                    if ([device lockForConfiguration:&error])
                    {
                        device.torchMode = AVCaptureTorchModeAuto;
                        [device unlockForConfiguration];
                    }
                }
                break;
		}
	}
}

#pragma mark - ZBar's Delegate methods

- (void)readerView:(ZBarReaderView *)view didReadSymbols:(ZBarSymbolSet *)syms fromImage:(UIImage *)img
{
    [self processZBarResults:syms];

    [view stop];
}

- (void)imagePickerController:(UIImagePickerController *)reader didFinishPickingMediaWithInfo:(NSDictionary*) info
{
    id<NSFastEnumeration> results = [info objectForKey:ZBarReaderControllerResults];
    //UIImage *image = [info objectForKey: UIImagePickerControllerOriginalImage];

    [self processZBarResults:(ZBarSymbolSet *)results];

    [reader dismissViewControllerAnimated:YES completion:nil];
    //[[controller presentingViewController] dismissViewControllerAnimated:YES completion:nil];
    //[reader dismissModalViewControllerAnimated: YES];
}

- (void)readerControllerDidFailToRead:(ZBarReaderController*)reader
                             withRetry:(BOOL)retry
{
    self.textPrivateKey.text = @"";
    [reader dismissViewControllerAnimated:YES completion:nil];

    UIAlertView *alert = [[UIAlertView alloc]
                          initWithTitle:NSLocalizedString(@"QR Code Scan Failure", nil)
                          message:NSLocalizedString(@"Unable to scan QR code", nil)
                          delegate:self
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil];
    [alert show];
}

#pragma mark UIAlertView delegates

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	// we only use an alert delegate when we have successfully imported

    [self performSelector:@selector(animatedExit) withObject:nil afterDelay:0.0];
}

@end

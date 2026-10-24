#import "AD.h"

@interface ADShelfController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate, UISearchBarDelegate>
@end

@interface ADPlayerController : UIViewController
@end

@interface ADSettingsController : UIViewController
@end

@interface ADBookController : UIViewController
@property (nonatomic, strong) ADBook *book;
@end

NSDictionary *ADUnwrapBook(id json);
NSArray<ADBook *> *ADBooksFromJSON(id json, NSString *listPath);

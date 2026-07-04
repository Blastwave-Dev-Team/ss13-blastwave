#define DEFAULT_UPLOAD_CATAGORY "Fiction"
#define DEFAULT_SEARCH_CATAGORY "Any"

///How many books should we load per page?
#define BOOKS_PER_PAGE 18
///How many checkout records should we load per page?
#define CHECKOUTS_PER_PAGE 17
///How many inventory items should we load per page?
#define INVENTORY_PER_PAGE 19

// Book categories, used in SQL so don't change randomly
#define BOOK_CATEGORY_FICTION "Fiction"
#define BOOK_CATEGORY_NONFICTION "Non-fiction"
#define BOOK_CATEGORY_RELIGION "Religion"
#define BOOK_CATEGORY_ADULT "Adult"
#define BOOK_CATEGORY_REFERENCE "Reference"
#define BOOK_CATEGORY_TEXTBOOK "Textbook"
/// If making a book of this category it will be randomly selected from all categories
#define BOOK_CATEGORY_RANDOM "Random"

/// Maximum length for a single UGC wiki page slug segment.
#define UGC_PAGE_SLUG_MAX_LEN 100
/// Maximum length for a full wiki page path (including nested segments).
#define WIKI_PAGE_PATH_MAX_LEN 200

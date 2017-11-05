#! /usr/bin/env perl

###########################################################################
##
##          FILE: checkwiki.pl
##
##         USAGE: ./checkwiki.pl -c checkwiki.cfg --project=<enwiki>
##                --load <live, dump, delay> --dumpfile --tt-file
##
##   DESCRIPTION: Scan Wikipedia articles for errors.
##
##        AUTHOR: Stefan Kühn, Bryan White
##       LICENCE: GPLv3
##       VERSION: 2016/11/30
##
###########################################################################

use strict;
use warnings;
#use lib '/data/project/checkwiki/perl5/perlbrew/perls/perl-5.24.0/lib/site_perl/5.24.0/';
use lib '/data/project/checkwiki/perl/lib/perl5';

use DBI;
use DBD::mysql;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use POSIX qw(strftime);

use Business::ISBN qw( valid_isbn_checksum );
use MediaWiki::API;
use MediaWiki::Bot;

#THESE TWO ARE LOADED AT RUNTIME BY IF STATEMENT JUST AFTER COMMAND-LINE ARE FOUND
#SPEEDS UP STARTUP
#use MediaWiki::DumpFile::Pages;
#use File::Temp;

binmode( STDOUT, ':encoding(UTF-8)' );

##############################
##  Program wide variables
##############################

my $Dump_or_Live = q{};    # Scan modus (dump, live, delay)

my $CheckOnlyOne = 0;      # Check only one error or all errors

my $ServerName  = q{};     # Address where api can be found
my $Language    = q{};     # Code of the language being used 'de' or 'en'
my $project     = q{};     # Name of the project 'dewiki'
my $end_of_dump = q{};     # When last article from dump reached
my $artcount    = 0;       # Number of articles processed
my $file_size   = 0;       # How many MB of the dump has been processed.

# Database configuration
my $DbName;
my $DbServer;
my $DbUsername;
my $DbPassword;

my $dbh;

# MediaWiki::DumpFile variables
my $pages = q{};

# Time program starts
my $time_start = time();    # Start timer in secound
my $time_end   = time();    # End time in secound
my $time_found = time();    # For column "Found" in cw_error

# Template list retrieved from Translation file
my @Template_list;

# Article name for article mode
my $ArticleName;

# Filename that contains a list of articles titles for list mode
my $ListFilename;

# Filename that contains the dump file for dump mode
my $DumpFilename;

# Should Template Tiger output be generated?
my $Template_Tiger = 0;
my $TTFile;
my $TTFilename;
my $TTDIRECTORY = '/data/project/templatetiger/public_html/dumps/';
my $TTnumber    = 0;

# Total number of Errors
my $Number_of_error_description = 0;

##############################
##  Wiki-special variables
##############################

#my @Namespace;    # Namespace values
# 0 number
# 1 namespace in project language
# 2 namespace in english language

my @Namespace_cat;          # All namespaces for categorys
my @Namespace_templates;    # All namespaces for templates
my @Template_regex;         # Template regex fron translation file
my $IMAGE_REGEX;            # Regex used in get_images()
my $Cat_regex = q{};        # Regex used in get_categories()
my $REGEX_095;              # Regex used in error_095_user_signature();

my @Magicword_defaultsort;

my $Error_counter = -1;     # Number of found errors in all article
my @ErrorPriority;          # Priority each error has

my @Error_number_counter = (0) x 150;    # Error counter for individual errors

my @FOUNDATION_PROJECTS;       # Names and shortcuts of Wikimedia foundation
my @INTER_LIST;                # Shortcuts to other language wikis
my @HTML_NAMED_ENTITIES;       # HTML names for symbols
my @HTML_NAMED_ENTITIES_011;   # HTML names for symbols minus some Greek letters
my @REGEX_003;
my @REGEX_002;
my @REGEX_BR_002;              # Regex used in #002
my $REGEX_SHORT_016;
my $REGEX_LONG_016;
my @REGEX_034;                 # Contains all of #034 Regexes
my @REGEX_034_BRACKET;         # Contains #034 regexes minues '{{{'
my @REGEX_061;
my @REGEX_078;
my $CHARACTERS_064;
my @REGEX_085;
my @REGEX_112;

##############################
##  Wiki-special variables
##############################

my @ack;

@FOUNDATION_PROJECTS = qw / b c d n m q s v w
  meta  mw  nost  wikt  wmf  voy
  commons     foundation   incubator   phabricator
  quality     species      testwiki    wikibooks
  wikidata    wikimedia    wikinews    wikiquote
  wikisource  wikispecies  wiktionary  wikiversity
  wikivoyage /;

@INTER_LIST = qw / af  als an  ar  az  bg  bs  bn
  ca  cs  cy  da  de  el  en  eo  es  et  eu  fa  fi
  fr  fy  gv  he  hi  hr  hu  hy  id  is  it  ja
  jv  ka  kk  ko  la  lb  lt  ms  nds nl  nn  no  pl
  pt  ro  ru  sh  sk  sl  sr  sv  sw  ta  th  tr  uk
  ur  uz  vi  zh  simple  nds_nl /;

# See http://turner.faculty.swau.edu/webstuff/htmlsymbols.html
@HTML_NAMED_ENTITIES = qw / aacute Aacute acute acirc Acirc aelig AElig
  agrave Agrave alpha Alpha aring Aring asymp atilde Atilde auml Auml beta Beta
  bdquo brvbar bull ccedil Ccedil cent chi Chi clubs copy crarr darr dArr deg
  delta Delta diams divide eacute Eacute ecirc Ecirc egrave Egrave
  epsilon Epsilon equiv eta Eta eth ETH euml Euml euro fnof frac12 frac14
  frac34 frasl gamma Gamma ge harr hArr hearts hellip iacute Iacute icirc Icirc
  iexcl igrave Igrave infin int iota Iota iquest iuml Iuml kappa Kappa
  lambda Lambda laquo larr lArr ldquo le loz lsaquo lsquo micro middot minus
  mu Mu ne not ntilde Ntilde nu Nu oacute Oacute ocirc Ocirc oelig OElig
  ograve Ograve oline omega Omega omicron Omicron ordf ordm oslash Oslash
  otilde Otilde ouml Ouml para part permil phi Phi pi Pi piv plusmn
  pound Prime prime prod psi Psi quot radic raquo rarr rArr rdquo reg rho Rho
  raquo rsaquo rsquo sbquo scaron Scaron sect sigma Sigma sigmaf spades
  sum sup1 sup2 sup3 szlig tau Tau theta Theta thetasym thorn THORN
  tilde times trade uacute Uacute uarr uArr ucirc Ucirc ugrave Ugrave upsih
  upsilon Upsilon uuml Uuml xi Xi yacute Yacute yen yuml Yuml zeta Zeta /;

# FOR #011. DO NOT CONVERT GREEK LETTERS THAT LOOK LIKE LATIN LETTERS.
# Alpha (A), Beta (B), Epsilon (E), Zeta (Z), Eta (E), Kappa (K), kappa (k), Mu (M), Nu (N), nu (v), Omicron (O), omicron (o), Rho (P), Tau (T), Upsilon (Y), upsilon (o) and Chi (X).
@HTML_NAMED_ENTITIES_011 = qw / aacute Aacute acute acirc Acirc aelig AElig
  agrave Agrave alpha aring Aring asymp atilde Atilde auml Auml beta bdquo
  brvbar bull ccedil Ccedil cent chi clubs copy crarr darr dArr deg
  delta Delta diams divide eacute Eacute ecirc Ecirc egrave Egrave
  epsilon equiv eta eth ETH euml Euml euro fnof frac12 frac14
  frac34 frasl gamma Gamma ge harr hArr hearts hellip iacute Iacute icirc
  Icirc iexcl igrave Igrave infin int iota Iota iquest iuml Iuml
  lambda Lambda laquo larr lArr ldquo le loz lsaquo lsquo micro middot minus
  mu ne not ntilde Ntilde oacute Oacute ocirc Ocirc oelig OElig
  ograve Ograve oline omega Omega ordf ordm oslash Oslash otilde Otilde ouml
  Ouml para part permil phi Phi pi Pi piv plusmn pound Prime prime prod
  psi Psi quot radic raquo rarr rArr rdquo reg rho raquo rsaquo rsquo sbquo
  scaron Scaron sect sigma Sigma sigmaf spades sum sup1 sup2 sup3 szlig
  tau theta Theta thetasym thorn THORN tilde times trade uacute Uacute uarr uArr
  ucirc Ucirc ugrave Ugrave upsih upsilon uuml Uuml xi Xi yacute Yacute
  yen yuml Yuml zeta Zeta /;

@ack = qw / abbr b big blockquote center cite
  del div em font i p s small span strike sub sup td th tr tt u /;

foreach my $item (@ack) {
    push @REGEX_002, qr/(<\s*\/?\s*$item\s*\/\s*>)/;
}

push @REGEX_BR_002, qr/<br\s*\/\s*[^ ]>/;      # <br\/t>
push @REGEX_BR_002, qr/<br[^ ]\/>/;            # <brt \/>
push @REGEX_BR_002, qr/<br[^ \/]>/;            # <brt>
push @REGEX_BR_002, qr/<br\s*\/\s*[^ >]/;      # <br
push @REGEX_BR_002, qr/<br\s*[^ >\/]/;         # <br
push @REGEX_BR_002, qr/<br\h*[^ \v>\/]/;       # <br t> \v is newline
push @REGEX_BR_002, qr/<[^ w]br[^\/]*\s*>/;    # <tbr> or < br>
push @REGEX_BR_002, qr/<\/hr>/;

$REGEX_SHORT_016 = qr/[\x{200E}\x{FEFF}]/;

# Below <...> are links to enwiki pages
#Readonly::Scalar $REGEX_LONG_016 =>
#  qr/[     \x{200E}   # <Left to right mark>
#           \x{200F}   # <Right to left mark>
#           \x{2004}   # Whitespace character (Three per em space)
#           \x{2005}   # <Whitespace character> (Four per em space or mid-space)
#           \x{2006}   # <Whitespace character> (Sixper em space)
#           \x{2007}   # <Whitespace character> (Figure space)
#           \x{2008}   # <Whitespace character> (Punctuation space)
#           \x{FEFF}   # <Specials (Unicode block)>
#           \x{007F}   # <Delete character>
#           \x{200B}   # <Zero width space>
#           \x{2028}   # <Newline> (Line Separator)
#           \x{202A}   # <Bi directional text> (Left to Right Embedding)
#           \x{202B}   # <Bi directional text> (Right to Left Embedding)
#           \x{202C}   # <Bi directional text> (Pop Directional Format)
#           \x{202D}   # <Bi directional text> (Left to Right Override)
#           \x{202E}   # <Bi directional text> (Right to Left Override)
#           \x{00A0}   # <Non breaking space>
#           \x{00AD}   # <Soft hyphen>
#           ]/x;
$REGEX_LONG_016 =
qr/[\x{200E}\x{FEFF}\x{007F}\x{200B}\x{2028}\x{202A}\x{202C}\x{202D}\x{202E}\x{00A0}\x{00AD}\x{202B}\x{200F}\x{2004}\x{2005}\x{2006}\x{2007}\x{2008}\x{FFC}]/;

push @REGEX_034, qr/#if:/;
push @REGEX_034, qr/#ifeq:/;
push @REGEX_034, qr/#switch:/;
push @REGEX_034, qr/#ifexist:/;
push @REGEX_034, qr/\{\{fullpagename}}/;
push @REGEX_034, qr/\{\{sitename}}/;
push @REGEX_034, qr/\{\{namespace}}/;
push @REGEX_034, qr/\{\{basepagename}}/;
push @REGEX_034, qr/\{\{pagename}}/;
push @REGEX_034, qr/\{\{subpagename}}/;
push @REGEX_034, qr/\{\{namespacenumber}}/;
push @REGEX_034, qr/\{\{fullpagenamee}}/;
push @REGEX_034, qr/\{\{subst:/;
push @REGEX_034, qr/__noindex__/;
push @REGEX_034, qr/__index__/;
push @REGEX_034, qr/__nonewsectionlink__/;

@REGEX_034_BRACKET = @REGEX_034;
push @REGEX_034_BRACKET, qr/\{\{\{/;

$CHARACTERS_064 = q{"'`‘«»„“”().,–־—};

push @REGEX_085, qr/<noinclude>\s*<\/noinclude>/;
push @REGEX_085, qr/<onlyinclude>\s*<\/onlyinclude/;
push @REGEX_085, qr/<includeonly>\s*<\/includeonly>/;
push @REGEX_085, qr/<center>\s*<\/center>/;
push @REGEX_085, qr/(<gallery[^>]*(?:\/>|>(?:\s|&nbsp;)*<\/gallery>))/;
push @REGEX_085, qr/<ref>\s*<\/ref>/;
push @REGEX_085, qr/<span(?!\s*id=)[^>]*>\s*<\/span>/;
push @REGEX_085, qr/#<div(?!\s*id=)[^>]*>\s*<\/div>/;
push @REGEX_085, qr/<div(?!(\s*id=|\s*style="clear))[^>]*>\s*<\/div>/;
push @REGEX_085, qr/<pre>\s*<\/pre>/;
push @REGEX_085, qr/<code>\s*<\/code>/;

push @REGEX_112, qr/[; ]-moz-/;
push @REGEX_112, qr/[; ]-webkit-/;
push @REGEX_112, qr/[; ]-ms-/;
push @REGEX_112, qr/[; ]data-cx-weight/;
push @REGEX_112, qr/[; ]contenteditable/;

###############################
## Variables for one article
###############################

my $title         = q{};    # Title of current article
my $text          = q{};    # Text of current article
my $lc_text       = q{};    # Text of current article in lower case
my $text_original = q{};    # Text of article with comments only removed

my $page_namespace;         # Namespace of page
my $page_is_redirect       = 'no';
my $page_is_disambiguation = 'no';

my $Category_counter = -1;

my @Category;               # 0 pos_start
                            # 1 pos_end
                            # 2 category	Test
                            # 3 linkname	Linkname
                            # 4 original	[[Category:Test|Linkname]]

my @Interwiki;              # 0 pos_start
                            # 1 pos_end
                            # 2 interwiki	Test
                            # 3 linkname	Linkname
                            # 4 original	[[de:Test|Linkname]]
                            # 5 language

my $Interwiki_counter = -1;

my @Templates_all;          # All templates
my @Template;               # Templates with values
                            # 0 number of template
                            # 1 templatename
                            # 2 template_row
                            # 3 attribut
                            # 4 value

my $Number_of_template_parts = -1;    # Number of all template parts

my @Links_all;                        # All links
my @Images_all;                       # All images
my @Ref;                              # All ref
my @Headlines;                        # All headlines
my @Lines;                            # Text seperated in lines

###########################################################################
###########################################################################
###########################################################################
## OPEN DATABASE
###########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : q{} ),
        $DbUsername,
        $DbPassword,
        {
            mysql_enable_utf8 => 1,
            mysql_auto_reconnect => 1,
        }
    ) or die( 'Could not connect to database: ' . DBI::errstr() . "\n" );

    return ();
}

###########################################################################
## CLOSE DATABASE
###########################################################################

sub close_db {

    $dbh->disconnect();

    return ();
}

###########################################################################
## DELETE OLD LIST OF ARTICLES FROM LAST DUMP SCAN IN TABLE cw_dumpscan
###########################################################################

sub clearDumpscanTable {

    my $sth = $dbh->prepare('DELETE FROM cw_dumpscan WHERE Project = ?;');
    $sth->execute($project);

    return ();
}

###########################################################################
## UPDATE DATE OF LAST DUMP IN DATABASE FOR PROJECT GIVEN
###########################################################################

sub updateDumpDate {
    my ($date) = @_;

    my $sth =
      $dbh->prepare('UPDATE cw_overview SET Last_Dump = ? WHERE Project = ?;');
    $sth->execute( $date, $project );

    return ();
}

###########################################################################
##
###########################################################################

sub update_ui {
    my $bytes = $pages->current_byte;

    if ( $file_size > 0 ) {
        my $percent = int( $bytes / $file_size * 100 );
        printf( "   %7d articles;%10s processed;%3d%% completed\n",
            ( $artcount, pretty_bytes($bytes), $percent ) );
    }
    else {
        printf( "   %7d articles;%10s processed\n",
            ( $artcount, pretty_bytes($bytes) ) );
    }

    return ();
}

###########################################################################
###
###########################################################################

sub pretty_number {
    my $number = reverse(shift);
    $number =~ s/(...)/$1,/g;
    $number = reverse($number);
    $number =~ s/^,//;

    return $number;

}

###########################################################################
###
##########################################################################

sub pretty_bytes {
    my ($bytes) = @_;
    my $pretty = int($bytes) . ' bytes';

    if ( ( $bytes = $bytes / 1024 ) > 1 ) {
        $pretty = int($bytes) . ' KB';
    }

    if ( ( $bytes = $bytes / 1024 ) > 1 ) {
        $pretty = sprintf( '%7.2f', $bytes ) . ' MB';
    }

    if ( ( $bytes = $bytes / 1024 ) > 1 ) {
        $pretty = sprintf( '%0.3f', $bytes ) . ' GB';
    }

    return ($pretty);
}

###########################################################################
###
###########################################################################

sub case_fixer {
    my ($my_title) = @_;

    # wiktionary article titles are case sensitive
    if ( $project !~ /wiktionary/ ) {

        #check for namespace
        if ( $my_title =~ /^(.+?):(.+)/ ) {
            $my_title = $1 . q{:} . ucfirst($2);
        }
        else {
            $my_title = ucfirst($title);
        }
    }

    return ($my_title);
}

###########################################################################
## RESET VARIABLES BEFORE SCANNING A NEW ARTICLE
###########################################################################

sub set_variables_for_article {
    $title = q{};    # title of the current article
    $text  = q{};    # text of the current article  (for work)

    $page_is_redirect       = 'no';
    $page_is_disambiguation = 'no';

    undef(@Category);    # 0 pos_start
                         # 1 pos_end
                         # 2 category	Test
                         # 3 linkname	Linkname
                         # 4 original	[[Category:Test|Linkname]]

    $Category_counter = -1;

    undef(@Interwiki);    # 0 pos_start
                          # 1 pos_end
                          # 2 interwiki	Test
                          # 3 linkname	Linkname
                          # 4 original	[[de:Test|Linkname]]
                          # 5 language

    $Interwiki_counter = -1;

    undef(@Lines);        # Text seperated in lines
    undef(@Headlines);    # Headlines

    undef(@Templates_all);    # All templates
    undef(@Template);         # Templates with values
                              # 0 number of template
                              # 1 templatename
                              # 2 template_row
                              # 3 attribut
                              # 4 value
    $Number_of_template_parts = -1;    # Number of all template parts

    undef(@Links_all);                 # All links
    undef(@Images_all);                # All images
    undef(@Ref);                       # All ref

    return ();
}

###########################################################################
## MOVE ARTICLES FROM cw_dumpscan INTO cw_error
###########################################################################

sub update_table_cw_error_from_dump {

    if ( $Dump_or_Live eq 'dump' ) {

        my $sth = $dbh->prepare('DELETE FROM cw_error WHERE Project = ?;');
        $sth->execute($project);

        $sth = $dbh->prepare(
'INSERT INTO cw_error (SELECT * FROM cw_dumpscan WHERE Project = ?);'
        );
        $sth->execute($project);

    }

    return ();
}

###########################################################################
## DELETE "DONE" ARTICLES FROM DB
###########################################################################

sub delete_done_article_from_db {

    my $sth =
      $dbh->prepare('DELETE FROM cw_error WHERE ok = 1 and project = ?;');
    $sth->execute($project);

    return ();
}

###########################################################################
## DELETE ARTICLE IN DATABASE
###########################################################################

sub delete_old_errors_in_db {
    if ( $Dump_or_Live eq 'live' && $title ne q{} ) {
        my $sth = $dbh->prepare(
            'DELETE FROM cw_error WHERE Title = ? AND Project = ?;');
        $sth->execute( $title, $project );
    }

    return ();
}

###########################################################################
## GET @ErrorPriority
###########################################################################

sub getErrors {
    my $error_count = 0;

    my $sth = $dbh->prepare(
        'SELECT COUNT(*) FROM cw_overview_errors WHERE project = ?;');
    $sth->execute($project);

    $Number_of_error_description = $sth->fetchrow();

    $Number_of_error_description = 112;

    $sth =
      $dbh->prepare('SELECT prio FROM cw_overview_errors WHERE project = ?;');
    $sth->execute($project);

    foreach my $i ( 1 .. $Number_of_error_description ) {
        $ErrorPriority[$i] = $sth->fetchrow();
        if ( $ErrorPriority[$i] > 0 ) {
            $error_count++;
        }
    }

    if ( $Dump_or_Live ne 'article' ) {
        two_column_display( 'Total # of errors possible:',
            $Number_of_error_description );
        two_column_display( 'Number of errors to process:', $error_count );
    }

    return ();
}

###########################################################################
##  Read Metadata from API
###########################################################################

sub readMetadata {

    my $image_regex_temp;
    my $user_regex  = q{};
    my $draft_regex = q{};

    $ServerName = $project;
    if (
        !(
               $ServerName =~ s/^nds_nlwiki$/nds-nl.wikipedia.org/
            || $ServerName =~ s/^([[:lower:]]+)wiki$/$1.wikipedia.org/
            || $ServerName =~ s/^([[:lower:]]+)wikisource$/$1.wikisource.org/
            || $ServerName =~ s/^([[:lower:]]+)wikiversity$/$1.wikiversity.org/
            || $ServerName =~ s/^([[:lower:]]+)wiktionary$/$1.wiktionary.org/
        )
      )
    {
        die( 'Couldn not calculate server name for project' . $project . "\n" );
    }

    ($Language) = $ServerName =~ /^([[:lower:]]*)/;

    my $sth = $dbh->prepare(
        'SELECT Metaparam, Templates FROM cw_meta WHERE Project = ?');
    $sth->execute($project);

    while ( my @value = $sth->fetchrow_array ) {
        if ( $value[0] eq 'magicword_defaultsort' ) {
            push( @Magicword_defaultsort, $value[1] );
        }
        elsif ( $value[0] eq 'namespace_templates' ) {
            push( @Namespace_templates, lc( $value[1] ) );
        }
        elsif ( $value[0] eq 'namespace_cat' ) {
            push( @Namespace_cat, $value[1] );
        }
        elsif ( $value[0] eq 'image_regex' ) {
            $image_regex_temp = $value[1];
        }
        elsif ( $value[0] eq 'cat_regex' ) {
            $Cat_regex = $value[1];
        }
        elsif ( $value[0] eq 'user_regex' ) {
            $user_regex = $value[1];
        }
        elsif ( $value[0] eq 'draft_regex' ) {
            $draft_regex = $value[1];
        }
    }

    # API goofs on cswiki
    if ( $project eq 'cswiki' ) {
        $user_regex =
'user:|\[\[diskuse s wikipedistou:|\[\[wikipedista:|\[\[redaktor:|\[\[uživatel:|\[\[wikipedistka:|\[\[diskuse s uživatelem:|\[\[diskuse s wikipedistkou:|\[\[diskusia s redaktorom:|\[\[komentár k redaktorovi:|\[\[uživatel diskuse:|\[\[uživatelka diskuse:|\[\[wikipedista diskuse:|\[\[wikipedistka diskuse';
    }

    my $image_lc = lc($image_regex_temp);
    $IMAGE_REGEX = qr/^\[\[\s*$image_regex_temp|$image_lc:/;
    $REGEX_095   = qr/$user_regex$draft_regex/;

    return ();
}

###########################################################################
##  READ TEMPLATES GIVEN IN TRANSLATION FILE
###########################################################################

sub readTemplates {

    my $template_sql;

    foreach my $i ( 1 .. $Number_of_error_description ) {

        $Template_list[$i][0] = '-9999';
        $Template_regex[$i] = q{};

        my $sth = $dbh->prepare(
            'SELECT templates FROM cw_template WHERE error=? AND project=?');
        $sth->execute( $i, $project );

        $sth->bind_col( 1, \$template_sql );
        while ( $sth->fetchrow_arrayref ) {
            if ( defined($template_sql) ) {
                if ( $Template_list[$i][0] eq '-9999' ) {
                    shift( @{ $Template_list[$i] } );
                    $Template_regex[$i] = '\{\{' . lc($template_sql) . q{|};
                }
                else {
                    $Template_regex[$i] =
                      $Template_regex[$i] . '\{\{' . lc($template_sql) . q{|};
                }
                push( @{ $Template_list[$i] }, lc($template_sql) );
            }
        }
    }

    foreach my $item ( @{ $Template_list[3] } ) {
        $item = lc($item);
        push @REGEX_003, qr/\{\{[ ]?$item/;
    }

    foreach my $item ( @{ $Template_list[61] } ) {
        $item = lc($item);
        push @REGEX_061, qr/\{\{[ ]?$item[^}]*[}]{2,4}[ ]{0,2}([.,?:;]|! )/;
    }

    foreach my $item ( @{ $Template_list[78] } ) {
        $item = lc($item);
        push @REGEX_078, qr/\{\{$item/;
    }

    return ();
}

###########################################################################
##
###########################################################################

sub scan_pages {

    $end_of_dump = 'no';
    my $page = q{};
    my $revision;

    if ( $Dump_or_Live eq 'dump' ) {

        $pages = MediaWiki::DumpFile::Pages->new($DumpFilename);

        # CHECK FILE_SIZE IF ONLY UNCOMPRESSED
        if ( $DumpFilename !~ /(?:.*?)\.xml\.bz2$/ ) {
            $file_size = ( stat($DumpFilename) )[7];
        }

        while ( defined( $page = $pages->next ) && $end_of_dump eq 'no' ) {
            next if ( $page->namespace != 0 );    #NS=0 IS ARTICLE NAMESPACE
            set_variables_for_article();
            $title = $page->title;
            if ( $title ne q{} ) {
                update_ui() if ++$artcount % 500 == 0;

                #if ( $artcount > 300500 ) {
                $page_namespace = 0;
                $title          = case_fixer($title);
                $revision       = $page->revision;
                $text           = $revision->text;
                check_article();

            }

            #$end_of_dump = 'yes' if ( $artcount > 1000 );

            #$end_of_dump = 'yes' if ( $Error_counter > 40000 )
            #}
        }
    }

    elsif ( $Dump_or_Live eq 'live' )    { live_scan(); }
    elsif ( $Dump_or_Live eq 'delay' )   { delay_scan(); }
    elsif ( $Dump_or_Live eq 'list' )    { list_scan(); }
    elsif ( $Dump_or_Live eq 'article' ) { article_scan(); }
    else                                 { die("Wrong Load_mode entered \n"); }

    return ();
}

###########################################################################
## CHECK ONE ARTICLE VIA A ARTICLE SCAN
###########################################################################

sub article_scan {

    $page_namespace = 0;
    my $bot = MediaWiki::Bot->new(
        {
            assert   => 'bot',
            protocol => 'https',
            host     => $ServerName,
            operator => 'CheckWiki',
        }
    );

    set_variables_for_article();
    utf8::decode($ArticleName);
    $text = $bot->get_text($ArticleName);
    if ( defined($text) ) {
        check_article();
    }

    return ();
}

###########################################################################
## CHECK ARTICLES VIA A LIST SCAN
###########################################################################

sub list_scan {

    $page_namespace = 0;
    my $bot = MediaWiki::Bot->new(
        {
            assert   => 'bot',
            protocol => 'https',
            host     => $ServerName,
            operator => 'CheckWiki',
        }
    );

    if ( !defined($ListFilename) ) {
        die "The filename of the list was not defined\n";
    }

    open( my $list_of_titles, '<:encoding(UTF-8)', $ListFilename )
      or die 'Could not open file ' . $ListFilename . "\n";
    my @articles = <$list_of_titles>;
    chomp @articles;
    close($list_of_titles)
      or die 'Could not close file ' . $list_of_titles . "\n";

    foreach my $row (@articles) {
        set_variables_for_article();
        $title = $row;
        $text  = $bot->get_text($title);
        if ( defined($text) ) {
            check_article();
        }
    }

    return ();
}

###########################################################################
## CHECK ARTICLES VIA A LIVE SCAN
###########################################################################

sub live_scan {

    my @live_titles;
    my $limit = 500;    # 500 is the max mediawiki allows
    $page_namespace = 0;

    my $bot = MediaWiki::Bot->new(
        {
            assert   => 'bot',
            protocol => 'https',
            host     => $ServerName,
            operator => 'CheckWiki',
        }
    );

    my @rc = $bot->recentchanges( { ns => $page_namespace, limit => $limit } );
    foreach my $hashref (@rc) {
        push( @live_titles, $hashref->{title} );
    }

    foreach (@live_titles) {
        set_variables_for_article();
        $title = $_;
        $text  = $bot->get_text($title);
        if ( defined($text) ) {
            check_article();
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub delay_scan {

    my @title_array;
    my $title_sql;
    $page_namespace = 0;

    my $bot = MediaWiki::Bot->new(
        {
            assert   => 'bot',
            protocol => 'https',
            host     => $ServerName,
            operator => 'CheckWiki',
        }
    );

    # Get titles gathered from live_scan.pl
    my $sth = $dbh->prepare('SELECT Title FROM cw_new WHERE Project = ?;');
    $sth->execute($project);

    $sth->bind_col( 1, \$title_sql );
    while ( $sth->fetchrow_arrayref ) {
        push( @title_array, $title_sql );
    }

    # Remove the articles. live_scan.pl is continuously adding new article.
    # So, need to remove before doing anything else.
    $sth = $dbh->prepare('DELETE FROM cw_new WHERE Project = ?;');
    $sth->execute($project);

    foreach (@title_array) {
        set_variables_for_article();
        $title = $_;
        if ( $title ne q{} ) {
            $text = $bot->get_text($title);
            printf( "  %7d articles done\n", $artcount )
              if ++$artcount % 500 == 0;

            # Article may have been deleted or an empty title
            if ( defined($text) ) {
                check_article();
            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub check_article {

    delete_old_errors_in_db();
    $text_original = $text;

    #------------------------------------------------------
    # Following alters text and must be run first
    #------------------------------------------------------

    # REMOVES FROM $text ANY CONTENT BETWEEN <!-- --> TAGS.
    # CALLS #05
    get_comments();

    # REMOVES FROM $text ANY CONTENT BETWEEN <nowiki> </nowiki> TAGS.
    # CALLS #23
    get_nowiki();

    # REMOVES FROM $text ANY CONTENT BETWEEN <pre> </pre> TAGS.
    # CALLS #24
    get_pre();

    # REMOVES FROM $text ANY CONTENT BETWEEN <code> </code> TAGS.
    # CALLS #15
    get_code();

    # REMOVE FROM $text ANY CONTENT BETWEEN <syntaxhighlight> TAGS.
    get_syntaxhighlight();

    # REMOVES FROM $text ANY CONTENT BETWEEN <source> </sources TAGS.
    # CALLS #014
    get_source();

    # REMOVES FROM $text ANY CONTENT BETWEEN <math> </math> TAGS.
    # Goes after code and syntaxhighlight so it doesn't catch <math.h>
    # CALLS #013
    get_math();

    # REMOVES FROM $text ANY CONTENT BETWEEN <ce> </ce> TAGS.
    get_ce();

    # REMOVE FROM $text ANY CONTENT BETWEEN <hiero> TAGS.
    get_hiero();

    # REMOVE FROM $text ANY CONTENT BETWEEN <score> TAGS.
    get_score();

    # REMOVE FROM $text ANY CONTENT BETWEEN <graph> TAGS.
    get_graph();

    # REMOVE FROM $text ANY CONTENT BETWEEN <mapframe> TAGS.
    get_mapframe();

    $lc_text = lc($text);

    #------------------------------------------------------
    # Following interacts with other get_* or error #'s
    #------------------------------------------------------

    # CREATES @Ref - USED IN #81
    if ( $ErrorPriority[81] > 0 ) {
        get_ref();
    }

    # CREATES @Templates_all - USED IN #12, #31
    # CALLS #43
    get_templates_all();

    # DOES TEMPLATETIGER
    # USES @Templates_all
    # CREATES @template - USED IN #59, #60

    get_template();

    # CREATES @Links_all & @Images_all-USED IN #65, #66, #67, #68, #74, #76, #82
    # CALLS #10
    get_links();

    # SETS $page_is_redirect
    check_for_redirect();

    # CREATES @Category - USED IN #17, #18, #21, #22, #37, #53, #91
    get_categories();

    # CREATES @Interwiki - USED IN #45, #51, #53
    get_interwikis();

    # CREATES @Lines
    # USED IN #02, #09, #26, #32, #34, #38, #39, #40-#42, #54,  #75
    create_line_array();

    # CREATES @Headlines
    # USES @Lines
    # USED IN #07, #08, #25, #44, #51, #52, #57, #58, #62, #83, #84, #92
    get_headlines();

    # EXCEPT FOR get_* THAT REMOVES TAGS FROM $text, FOLLOWING DON'T NEED
    # TO BE PROCESSED BY ANY get_* ROUTINES: 3-6, 11, 13-16, 19, 20, 23, 24,
    # 27, 35, 36, 43, 46-50, 54-56, 59-61, 63-74, 76-80, 82, 84-90
    error_check();

    return ();
}

###########################################################################
## FIND MISSING COMMENTS TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_comments {

    if ( $text =~ /<!--/ ) {
        my $comments_begin = 0;
        my $comments_end   = 0;

        $comments_begin = () = $text =~ /<!--/g;
        $comments_end   = () = $text =~ /-->/g;

        if ( $comments_begin > $comments_end ) {
            my $snippet = get_broken_tag( '<!--', '-->' );
            error_005_Comment_no_correct_end($snippet);
        }

        $text =~ s/<!--(.*?)-->//sg;
    }

    return ();
}

###########################################################################
## FIND MISSING NOWIKI TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_nowiki {

    # Convert to lower case is alot faster then the regex /i option
    my $test_text    = lc($text);
    my $nowiki_begin = () = $test_text =~ /<nowiki>/g;
    my $nowiki_end   = () = $test_text =~ /<\/nowiki>/g;

    if ( $nowiki_begin != $nowiki_end ) {
        if ( $nowiki_begin > $nowiki_end ) {
            my $snippet = get_broken_tag( '<nowiki>', '</nowiki>' );
            error_023_nowiki_no_correct_end($snippet);
        }
        else {
            my $snippet = get_broken_tag_closing( '<nowiki>', '</nowiki>' );
            error_023_nowiki_no_correct_end($snippet);
        }
    }

    #Don't remove ISBN inside <nowiki> for #69 check
    $text =~ s/<nowiki>(?!ISBN)(.)*?<\/nowiki>/<nowiki>CheckWiki<\/nowiki>/sg;

    return ();
}

###########################################################################
## FIND MISSING PRE TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_pre {

    my $test_text = lc($text);
    my $pre_begin = () = $test_text =~ /<pre/g;
    my $pre_end   = () = $test_text =~ /<\/pre>/g;

    if ( $pre_begin != $pre_end ) {
        if ( $pre_begin > $pre_end ) {
            my $snippet = get_broken_tag( '<pre', '</pre>' );
            error_024_pre_no_correct_end($snippet);
        }
        else {
            my $snippet = get_broken_tag_closing( '<pre', '</pre>' );
            error_024_pre_no_correct_end($snippet);
        }
    }

    $text =~ s/<pre>(.*?)<\/pre>/<pre>CheckWiki<\/pre>/sg;

    return ();
}

###########################################################################
## FIND MISSING MATH TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_math {

    my $test_text  = lc($text);
    my $math_begin = () = $test_text =~ /<math/g;
    my $math_end   = () = $test_text =~ /<\/math>/g;

    if ( $math_begin != $math_end ) {
        if ( $math_begin > $math_end ) {
            my $snippet = get_broken_tag( '<math', '</math>' );
            error_013_Math_no_correct_end($snippet);
        }
        else {
            my $snippet = get_broken_tag_closing( '<math', '</math>' );
            error_013_Math_no_correct_end($snippet);
        }
    }

    $text =~ s/<math(.*?)<\/math>/<math>CheckWiki<\/math>/sg;

    return ();
}

###########################################################################
## FIND MISSING CE TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_ce {

    $text =~ s/<ce(.*?)<\/ce>/<ce>CheckWiki<\/ce>/sgi;

    return ();
}

###########################################################################
## FIND MISSING SOURCE TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_source {

    my $test_text    = lc($text);
    my $source_begin = () = $test_text =~ /<source/g;
    my $source_end   = () = $test_text =~ /<\/source>/g;

    if ( $source_begin != $source_end ) {
        if ( $source_begin > $source_end ) {
            my $snippet = get_broken_tag( '<source', '</source>' );
            error_014_Source_no_correct_end($snippet);
        }
        else {
            my $snippet = get_broken_tag_closing( '<source', '</source>' );
            error_014_Source_no_correct_end($snippet);
        }
    }

    $text =~ s/<source(.*?)<\/source>/<source>CheckWiki<\/source>/sg;

    return ();
}

###########################################################################
## FIND MISSING CODE TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_code {

    my $test_text  = lc($text);
    my $code_begin = () = $test_text =~ /<code/g;
    my $code_end   = () = $test_text =~ /<\/code>/g;

    if ( $code_begin != $code_end ) {
        if ( $code_begin > $code_end ) {
            my $snippet = get_broken_tag( '<code', '</code>' );
            error_015_Code_no_correct_end($snippet);
        }
        else {
            my $snippet = get_broken_tag_closing( '<code', '</code>' );
            error_015_Code_no_correct_end($snippet);
        }
    }

    $text =~ s/<code>(.*?)<\/code>/<code>CheckWiki<\/code>/sg;

    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE SYNTAXHIGHLIGHT TAGS
###########################################################################

sub get_syntaxhighlight {
    my $test_text = lc($text);

    if ( $test_text =~ /<syntaxhighlight/ ) {
        my $source_begin = 0;
        my $source_end   = 0;

        $source_begin = () = $test_text =~ /<syntaxhighlight/g;
        $source_end   = () = $test_text =~ /<\/syntaxhighlight>/g;

        if ( $source_begin > $source_end ) {
            my $snippet =
              get_broken_tag( '<syntaxhighlight', '</syntaxhighlight>' );
            error_014_Source_no_correct_end($snippet);
        }

        $text =~ s/<syntaxhighlight(.*?)<\/syntaxhighlight>/
                 <syntaxhighlight>CheckWiki<\/syntaxhighlight>/sgx;
    }

    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE HIERO TAGS
###########################################################################

sub get_hiero {

    $text =~ s/<hiero>(.*?)<\/hiero>/<hiero>CheckWiki<\/hiero>/sg;

    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE SCORE TAGS
###########################################################################

sub get_score {

    $text =~ s/<score(.*?)<\/score>/<score>CheckWiki<\/score>/sg;

    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE GRAPH TAGS
###########################################################################

sub get_graph {

    $text =~ s/<graph(.*?)<\/graph>/<graph>CheckWiki<\/graph>/sg;
    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE MAPFRAME TAGS
###########################################################################

sub get_mapframe {

    $text =~ s/<mapframe(.*?)<\/mapframe>/<mapframe>CheckWiki<\/mapframe>/sg;
    return ();
}

###########################################################################
## GET TABLES
###########################################################################

sub get_tables {

    my $test_text = $text;

    my $tag_open_num = () = $test_text =~ /\{\|/g;

    #  Alot of templates end with |}}, so exclude these.
    $test_text =~ s/\|\}\}//g;
    my $tag_close_num = () = $test_text =~ /\|\}/g;

    my $diff = $tag_open_num - $tag_close_num;

    if ( $diff > 0 ) {

        my $look_ahead_open  = 0;
        my $look_ahead_close = 0;
        my $look_ahead       = 0;

        my $pos_open  = index( $test_text, '{|' );
        my $pos_open2 = index( $test_text, '{|', $pos_open + 2 );
        my $pos_close = index( $test_text, '|}' );
        while ( $diff > 0 ) {
            if ( $pos_open2 == -1 ) {
                error_028_table_no_correct_end(
                    substr( $text, $pos_open, 40 ) );
                $diff = -1;
            }
            elsif ( $pos_open2 < $pos_close and $look_ahead > 0 ) {
                error_028_table_no_correct_end(
                    substr( $text, $pos_open, 40 ) );
                $diff--;
            }
            else {
                $pos_open  = $pos_open2;
                $pos_open2 = index( $test_text, '{|', $pos_open + 2 );
                $pos_close = index( $test_text, '|}', $pos_close + 2 );
                if ( $pos_open2 > 0 ) {
                    $look_ahead_open =
                      index( $test_text, '{|', $pos_open2 + 2 );
                    $look_ahead_close =
                      index( $test_text, '|}', $pos_close + 2 );
                    $look_ahead = $look_ahead_close - $look_ahead_open;
                }
            }
        }
    }

    return ();
}

###########################################################################
## GET ISBN
###########################################################################

sub get_isbn {

    if (
            index( $text, 'ISBN' ) > 0
        and $title ne 'International Standard Book Number'
        and $title ne 'ISBN'
        and $title ne 'ISBN-10'
        and $title ne 'ISBN-13'
        and $title ne 'Internationaal Standaard Boeknummer'
        and $title ne 'International Standard Book Number'
        and $title ne 'European Article Number'
        and $title ne 'Internationale Standardbuchnummer'
        and $title ne 'Buchland'
        and $title ne 'Codice ISBN'
        and index( $title, 'ISBN' ) == -1

      )
    {

        while ( $text =~ /ISBN([-=: ])/g ) {
            my $pos_start = pos($text) - 5;
            my $current_isbn = substr( $text, $pos_start );

            $current_isbn =~
/\b(?:ISBN(?:-?1[03])?:?\s*|(ISBN\s*=\s*))([\dX ‐—–-]{4,24}[\dX])\b/gi;

            if ( defined $2 ) {
                my $isbn       = $2;
                my $isbn_strip = $2;
                $isbn_strip =~ s/[^0-9X]//g;

                my $digits = length($isbn_strip);

                if ( index( $isbn_strip, 'X' ) > -1 ) {
                    if ( index( $isbn_strip, 'X' ) != 9 ) {
                        error_071_isbn_wrong_pos_X($isbn);
                    }
                }
                elsif ( $digits == 10 ) {
                    if ( valid_isbn_checksum($isbn_strip) != 1 ) {
                        error_072_isbn_10_wrong_checksum($isbn);
                    }
                }
                elsif ( $digits == 13 ) {
                    if ( valid_isbn_checksum($isbn_strip) != 1 ) {
                        error_073_isbn_13_wrong_checksum($isbn);
                    }
                }
                else {
                    error_070_isbn_wrong_length($isbn);
                }
            }
        }
    }

    return ();
}

###########################################################################
## GET ISSN
###########################################################################

sub get_issn {

    while ( $text =~ /(ISSN\s+[\dXx-]+)/g ) {
        my $output = $1;
        my $issn   = uc($1);
        $issn =~ s/[^0-9X]//g;
        my $length = length($issn);
        if ( $length < 8 or $length > 8 ) {
            error_107_issn_wrong_length($output);
        }
        elsif ( $issn !~ /\d{7}[\dX]/ ) {

            # X is in wrong spot
            error_108_issn_wrong_checksum($output);
        }
        else {
            my @digits = split //, $issn;
            my $sum = 0;
            foreach ( reverse 2 .. 8 ) {
                $sum += $_ * ( shift @digits );
            }
            my $checksum = ( 11 - ( $sum % 11 ) ) % 11;
            $checksum = 'X' if $checksum == 10;
            if ( substr( $issn, -1, 1 ) ne $checksum ) {
                error_108_issn_wrong_checksum($output);
            }
        }
    }

    return ();
}

###########################################################################
##  GET_REF
###########################################################################

sub get_ref {

    my $pos_start_old = 0;
    my $end_search    = 0;

    while ( $end_search == 0 ) {
        my $pos_start = 0;
        my $pos_end   = 0;
        $end_search = 1;

        $pos_start = index( $text, '<ref>',  $pos_start_old );
        $pos_end   = index( $text, '</ref>', $pos_start );

        if ( $pos_start > -1 and $pos_end > -1 ) {

            $pos_end       = $pos_end + length('</ref>');
            $end_search    = 0;
            $pos_start_old = $pos_end;

            push( @Ref, substr( $text, $pos_start, $pos_end - $pos_start ) );
        }
    }

    return ();
}

###########################################################################
## GET TEMPLATES ALL
###########################################################################

sub get_templates_all {

    my $temp_text_2 = q{};
    my $pos_start   = 0;
    my $pos_end     = 0;
    my $test_text   = $text;
    my $found_error = 0;

    # Delete all breaks --> only one line
    # Delete all tabs --> better for output
    $test_text =~ s/[\n\t]//g;

    if ( $text =~ /\{\{/g ) {    # Article may not have a template.
        $TTnumber++;
    }

    while ( $test_text =~ /\{\{/g ) {

        # DUE TO PERFORMANCE REASONS, USE FOLLOWING WITH PERL < 5.20
        my $temp_text = substr( $test_text, pos($test_text) - 2 );

        # COMMENT OUT ABOVE AND UNCOMMENT FOLLOWING LINE WITH PERL => 5.20
        # $pos_start = $-[0];

        my $brackets_begin = 1;
        my $brackets_end   = 0;

        while ( $temp_text =~ /\}\}/g ) {

            # Find currect end - number of {{ == }}
            $temp_text_2 =
              q{ } . substr( $temp_text, 0, pos($temp_text) ) . q{ };

            # Test the number of {{ and  }}
            $brackets_begin = ( $temp_text_2 =~ tr/{{/{{/ );
            $brackets_end   = ( $temp_text_2 =~ tr/}}/}}/ );

            last if ( $brackets_begin == $brackets_end );
        }

        if ( $brackets_begin == $brackets_end ) {

            # Template is correct
            $temp_text_2 = substr( $temp_text_2, 1, length($temp_text_2) - 2 );
            push( @Templates_all, $temp_text_2 );
        }
        elsif ( $found_error == 0 ) {
            my $begin_string = substr( $temp_text, 0, 40 );
            $found_error++;
            if ( $project ne 'ruwiki' and $project ne 'ukwiki' ) {
                error_043_template_no_correct_end($begin_string);
            }

            # ruwiki and ukwiki use "{{{!" in infoboxes.
            # Only look at beginning of string, where error is at. Bypass {{{!
            # but can continue on and check for error in rest of article.
            elsif ( $begin_string !~ /\{\{\{\!/ ) {
                error_043_template_no_correct_end($begin_string);
            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_template {

    # Extract for each template all attributes and values
    my $number_of_templates   = -1;
    my $template_part_counter = -1;
    my $output                = q{};
    foreach my $current_template (@Templates_all) {

        $current_template =~ s/^\{\{//;
        $current_template =~ s/\}\}$//;
        $current_template =~ s/^ //g;

        foreach (@Namespace_templates) {
            $current_template =~ s/^$_://i;
        }

        $number_of_templates++;
        my $template_name = q{};

        my @template_split = split( /\|/, $current_template );

        if ( index( $current_template, q{|} ) == -1 ) {

            # If no pipe; for example {{test}}
            $template_name = $current_template;
            next;
        }

        if ( index( $current_template, q{|} ) > -1 ) {

            # Templates with pipe {{test|attribute=value}}

            # Get template name
            $template_split[0] =~ s/^ //g;
            $template_name = $template_split[0];

            if ( index( $template_name, q{_} ) > -1 ) {
                $template_name =~ tr/_/ /;
            }
            if ( index( $template_name, q{  } ) > -1 ) {
                $template_name =~ tr/  / /s;
            }

            shift(@template_split);

            # Get next part of template
            my $template_part = q{};
            my @template_part_array;
            undef(@template_part_array);

            foreach (@template_split) {
                $template_part = $template_part . $_;

                # Check for []
                my $beginn_brackets = ( $template_part =~ tr/[/[/ );
                my $end_brackets    = ( $template_part =~ tr/]/]/ );

                # Check for {}
                my $beginn_curly_brackets = ( $template_part =~ tr/{/{/ );
                my $end_curly_brackets    = ( $template_part =~ tr/}/}/ );

                # Template part complete ?
                if (    $beginn_brackets eq $end_brackets
                    and $beginn_curly_brackets eq $end_curly_brackets )
                {

                    push( @template_part_array, $template_part );
                    $template_part = q{};
                }
                else {
                    $template_part = $template_part . q{|};
                }

            }

            # OUTPUT If only templates {{{xy|value}}
            my $template_part_number           = -1;
            my $template_part_without_attribut = -1;

            foreach my $part (@template_part_array) {

                $template_part_counter++;
                $template_part_number++;

                $Template[$template_part_counter][0] = $number_of_templates;
                $Template[$template_part_counter][1] = $template_name;
                $Template[$template_part_counter][2] = $template_part_number;

                my $attribut = q{};
                my $value    = q{};

                if ( index( $part, q{=} ) > -1 ) {

                    my $pos_equal     = index( $part, q{=} );
                    my $pos_lower     = index( $part, q{<} );
                    my $pos_next_temp = index( $part, '{{' );
                    my $pos_table     = index( $part, '{|' );
                    my $pos_bracket   = index( $part, q{[} );

                    my $equal_ok = 'true';
                    $equal_ok = 'false'
                      if ( $pos_lower > -1 and $pos_lower < $pos_equal );
                    $equal_ok = 'false'
                      if (  $pos_next_temp > -1
                        and $pos_next_temp < $pos_equal );
                    $equal_ok = 'false'
                      if ( $pos_table > -1 and $pos_table < $pos_equal );
                    $equal_ok = 'false'
                      if ( $pos_bracket > -1 and $pos_bracket < $pos_equal );

                    if ( $equal_ok eq 'true' ) {

                        # Template part with "="   {{test|attribut=value}}
                        $attribut = substr( $part, 0, index( $part, q{=} ) );
                        $value = substr( $part, index( $part, q{=} ) + 1 );
                    }
                    else {
                      # Problem  {{test|value<ref name="sdfsdf"> sdfhsdf</ref>}}
                      # Problem   {{test|value{{test2|name=teste}}|sdfsdf}}
                        $template_part_without_attribut =
                          $template_part_without_attribut + 1;
                        $attribut = $template_part_without_attribut;
                        $value    = $part;
                    }
                }
                else {
                    # Template part with no "="   {{test|value}}
                    $template_part_without_attribut =
                      $template_part_without_attribut + 1;
                    $attribut = $template_part_without_attribut;
                    $value    = $part;
                }

                # Output for TemplateTiger
                if ( $Template_Tiger == 1 ) {
                    $template_name =~ s/^\s+|\s+$//g;
                    $Template[$template_part_counter][1] = $template_name;

                    $attribut =~ s/^\s*|\s*$//g;
                    $value =~ s/^\s*|\s*$//g;
                    $Template[$template_part_counter][3] = $attribut;
                    $Template[$template_part_counter][4] = $value;

                    $output = q{};
                    $output .= $TTnumber . "\t";
                    $output .= $title . "\t";
                    $output .= $Template[$template_part_counter][0] . "\t";
                    $output .= $Template[$template_part_counter][1] . "\t";
                    $output .= $Template[$template_part_counter][2] . "\t";
                    $output .= $Template[$template_part_counter][3] . "\t";
                    $output .= $Template[$template_part_counter][4] . "\n";
                    $TTFile->print($output);
                }
                else {
                    $Template[$template_part_counter][3] = $attribut;
                    $Template[$template_part_counter][4] = $value;
                    $Number_of_template_parts++;
                }
            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_links {

    my $test_text   = $text;
    my $string_2    = q{};
    my $count_error = 1;       # Only report one error. Don't clutter up output

    while ( $test_text =~ /\[\[/g ) {

        my $link_text = substr( $test_text, pos($test_text) - 2 );

        my $left  = index( $link_text, '[[', 2 );
        my $right = index( $link_text, ']]', 2 );

        if ( $right < $left or ( $right > 0 and $left == -1 ) ) {
            my $string = substr( $text, pos($test_text) - 2, $right + 2 );
            my $string_left = index( $string, '[', 2 );
            my $string_right = rindex( $string, ']', 2 );
            if ( $string_left = $string_right ) {
                push_link($string);
            }
            else {
                if ( $count_error == 1 ) {
                    error_010_count_square_breaks($string);
                    $count_error = 0;
                }
            }
        }
        else {
            my $string = substr( $test_text, pos($test_text) - 2 );
            my $brackets_begin;
            my $brackets_end;

            while ( $string =~ /\]\]/g ) {

                $string_2 = substr( $string, 0, pos($string) );

                $brackets_begin = ( $string_2 =~ tr/[/[/ );
                $brackets_end   = ( $string_2 =~ tr/]/]/ );

                last if ( $brackets_begin == $brackets_end );
            }

            if ( $brackets_begin == $brackets_end ) {
                push_link($string_2);

            }
            else {
                if ( $count_error == 1 ) {
                    my $begin_string = substr( $string, 0, 40 );
                    error_010_count_square_breaks(
                        substr( $begin_string, 0, 40 ) );
                    $count_error = 0;
                }
            }
        }
    }

    return ();
}

sub push_link {
    my ($string) = @_;

    push( @Links_all, $string );

    if ( $string =~ /$IMAGE_REGEX/ ) {
        push( @Images_all, $string );
    }

    return ();
}

###########################################################################
##
###########################################################################

sub check_for_redirect {

    if ( index( $lc_text, '#redirect' ) > -1 ) {
        $page_is_redirect = 'yes';
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_categories {

    foreach my $namespace_cat_word (@Namespace_cat) {

        my $pos_end     = 0;
        my $pos_start   = 0;
        my $counter     = 0;
        my $test_text   = $text;
        my $search_word = $namespace_cat_word;

        while ( $test_text =~ /\[\[([ ]+)?$search_word\s*:/ig ) {
            $pos_start = pos($test_text) - length($search_word) - 1;
            $pos_end   = index( $test_text, ']]', $pos_start );
            $pos_start = $pos_start - 2;

            if ( $pos_start > -1 and $pos_end > -1 ) {

                $counter               = ++$Category_counter;
                $pos_end               = $pos_end + 2;
                $Category[$counter][0] = $pos_start;
                $Category[$counter][1] = $pos_end;
                $Category[$counter][4] =
                  substr( $test_text, $pos_start, $pos_end - $pos_start );
                $Category[$counter][2] = $Category[$counter][4];
                $Category[$counter][3] = $Category[$counter][4];

                $Category[$counter][2] =~ s/\[//g;          # Delete [[
                $Category[$counter][2] =~ s/^([ ]+)?//g;    # Delete blank
                $Category[$counter][2] =~ s/\]\]//g;        # Delete ]]
                $Category[$counter][2] =~ s/^$namespace_cat_word//i;
                $Category[$counter][2] =~ s/^ ?://;         # Delete :
                $Category[$counter][2] =~ s/\|(.)*//g;      # Delete |xy
                $Category[$counter][2] =~ s/^ //g;          # Delete blank
                $Category[$counter][2] =~ s/ $//g;          # Delete blank

                # Filter linkname
                $Category[$counter][3] = q{}
                  if ( index( $Category[$counter][3], q{|} ) == -1 );
                $Category[$counter][3] =~ s/^(.)*\|//gi; # Delete [[category:xy|
                $Category[$counter][3] =~ s/\]\]//g;     # Delete ]]
                $Category[$counter][3] =~ s/^ //g;       # Delete blank
                $Category[$counter][3] =~ s/ $//g;       # Delete blank

            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub get_interwikis {

    if ( $lc_text =~ /\[\[([[:lower:]][[:lower:]]|als|nds|nds_nl|simple):/ ) {

        foreach my $current_lang (@INTER_LIST) {

            my $pos_start   = 0;
            my $pos_end     = 0;
            my $counter     = 0;
            my $test_text   = $lc_text;
            my $search_word = $current_lang;

            while ( $test_text =~ /\[\[$search_word:/g ) {
                $pos_start = pos($test_text) - length($search_word) - 1;
                $pos_end   = index( $test_text, ']]', $pos_start );
                $pos_start = $pos_start - 2;

                if ( $pos_start > -1 and $pos_end > -1 ) {

                    $counter                = ++$Interwiki_counter;
                    $pos_end                = $pos_end + 2;
                    $Interwiki[$counter][0] = $pos_start;
                    $Interwiki[$counter][1] = $pos_end;
                    $Interwiki[$counter][4] =
                      substr( $text, $pos_start, $pos_end - $pos_start );
                    $Interwiki[$counter][5] = $current_lang;
                    $Interwiki[$counter][2] = $Interwiki[$counter][4];
                    $Interwiki[$counter][3] = $Interwiki[$counter][4];

                    $Interwiki[$counter][2] =~ s/\]\]//g;       # Delete ]]
                    $Interwiki[$counter][2] =~ s/\|(.)*//g;     # Delete |xy
                    $Interwiki[$counter][2] =~ s/^(.)*://gi;    # Delete [[xx:
                    $Interwiki[$counter][2] =~ s/^ //g;         # Delete blank
                    $Interwiki[$counter][2] =~ s/ $//g;         # Delete blank;

                    if ( index( $Interwiki[$counter][3], q{|} ) == -1 ) {
                        $Interwiki[$counter][3] = q{};
                    }

                    $Interwiki[$counter][3] =~ s/^(.)*\|//gi;
                    $Interwiki[$counter][3] =~ s/\]\]//g;
                    $Interwiki[$counter][3] =~ s/^ //g;
                    $Interwiki[$counter][3] =~ s/ $//g;
                }
            }
        }
    }

    return ();
}

###########################################################################
##
###########################################################################

sub create_line_array {
    @Lines = split( /\n/, $text );

    return ();
}

###########################################################################
##
###########################################################################

sub get_headlines {

    my $first = 0;
    foreach my $line (@Lines) {
        if ( substr( $line, 0, 1 ) eq q{=} ) {
            push( @Headlines, $line );
        }
    }

    return ();
}

##########################################################################
##
##########################################################################

sub get_broken_tag {
    my ( $tag_open, $tag_close ) = @_;
    my $text_snippet = q{};
    my $found        = -1;    # Open tag could be at position 0

    my $test_text = lc($text);

    if ( $tag_open eq '<ref' ) {
        $test_text =~ s/<ref name=[^\/]*\/>//sg;
        $test_text =~ s/<references\s*\/?\s*>//sg;
    }

    my $pos_open  = index( $test_text, $tag_open );
    my $pos_open2 = index( $test_text, $tag_open, $pos_open + 3 );
    my $pos_close = index( $test_text, $tag_close );

    while ( $found == -1 ) {
        if ( $pos_open2 == -1 ) {    # End of article and no closing tag found
            $found = $pos_open;
        }
        elsif ( $pos_open2 < $pos_close ) {
            $found = $pos_open;
        }
        else {
            $pos_open  = $pos_open2;
            $pos_open2 = index( $test_text, $tag_open, $pos_open + 3 );
            $pos_close = index( $test_text, $tag_close, $pos_close + 3 );
        }
    }

    if ( $tag_open eq '<ref' ) {
        $test_text = $text;
        $test_text =~ s/<ref name=[^\/]*\/>//sg;
        $test_text =~ s/<references\s*\/?\s*>//sg;
        $text_snippet = substr( $test_text, $found, 40 );
    }
    else {
        $text_snippet = substr( $text, $found, 40 );
    }

    return ($text_snippet);
}

##########################################################################
##
##########################################################################

sub get_broken_tag_closing {
    my ( $tag_open, $tag_close ) = @_;
    my $text_snippet = q{};
    my $found        = -2;    # Open tag could be at position 0
    my $ref_open     = 1;

    my $test_text = lc($text);

    if ( $tag_open eq '<ref' ) {
        $test_text =~ s/<ref name=[^\/]*\/>//sg;
        $test_text =~ s/<references\s*\/?\s*>//sg;
    }

    my $pos_close  = rindex( $test_text, $tag_close );
    my $pos_close2 = rindex( $test_text, $tag_close, $pos_close - 3 );
    my $pos_open   = rindex( $test_text, $tag_open );

    while ( $found == -2 ) {
        if ( $tag_open eq '<ref' ) {
            my $temp = substr( $test_text, $pos_open, 5 );
            if ( $temp ne '<ref>' and $temp ne '<ref ' ) {
                $ref_open = 0;
            }
        }

        my $ack = substr( $test_text, $pos_close, 12 );
        my $aco = substr( $test_text, $pos_open,  12 );

        # BEGINNING OF ARTICLE AND NO OPENING TAG FOUND
        if ( $pos_open == -1 ) {
            $found = $pos_close2;

            # ONLY ONE BROKEN TAG IN ARTICLE AND NO OPENING TAGS
            if ( $pos_close2 == -1 ) {
                $found = $pos_close;
            }
        }
        elsif ( $pos_close2 == -1 ) {
            $found = $pos_close;
        }
        elsif ( $pos_close2 > $pos_open ) {
            $found = $pos_close;
        }
        else {
            $pos_close  = $pos_close2;
            $pos_close2 = rindex( $test_text, $tag_close, $pos_close - 3 );
            $pos_open   = rindex( $test_text, $tag_open, $pos_open - 3 );
        }
    }
    $text_snippet = substr( $test_text, $found, 40 );

    return ($text_snippet);
}

##########################################################################
##
##########################################################################

sub error_check {
    if ( $CheckOnlyOne > 0 ) {
        error_061_reference_with_punctuation();
    }
    else {
        get_tables();    # CALLS #28
        get_isbn();      # CALLS #70, #71, #72 ISBN CHECKS
        get_issn();      # CALLS #107, #108 ISSN CHECKS

        error_001_word_template()  if ( $ErrorPriority[1] > 0 );
        error_002_have_br()        if ( $ErrorPriority[2] > 0 );
        error_003_have_ref()       if ( $ErrorPriority[3] > 0 );
        error_004_html_element_a() if ( $ErrorPriority[4] > 0 );

        #error_005_Comment_no_correct_end('');             # get_comments()
        error_006_defaultsort_special_letter() if ( $ErrorPriority[6] > 0 );
        error_007_headline_only_three()        if ( $ErrorPriority[7] > 0 );
        error_008_headline_start_end()         if ( $ErrorPriority[8] > 0 );
        error_009_multiple_category_in_line()  if ( $ErrorPriority[9] > 0 );

        #error_010_count_square_breaks('');                # get_links()
        error_011_html_named_entities() if ( $ErrorPriority[11] > 0 );
        error_012_html_list_elements()  if ( $ErrorPriority[12] > 0 );

        #error_013_Math_no_correct_end('');                # get_math
        #error_014_Source_no_correct_end('');              # get_source()
        #error_015_Code_no_correct_end('');                # get_code()
        error_016_unicode_control_character() if ( $ErrorPriority[16] > 0 );
        error_017_category_double()           if ( $ErrorPriority[17] > 0 );
        error_018_category_1st_letter_small() if ( $ErrorPriority[18] > 0 );
        error_019_headline_only_one()         if ( $ErrorPriority[19] > 0 );
        error_020_symbol_for_dead()           if ( $ErrorPriority[20] > 0 );
        error_021_category_is_english()       if ( $ErrorPriority[21] > 0 );
        error_022_category_with_space()       if ( $ErrorPriority[22] > 0 );

        #error_023_nowiki_no_correct_end('');              # get_nowiki()
        #error_024_pre_no_correct_end('');                 # get_pre()
        error_025_headline_hierarchy()       if ( $ErrorPriority[25] > 0 );
        error_026_html_text_style_elements() if ( $ErrorPriority[26] > 0 );
        error_027_unicode_syntax()           if ( $ErrorPriority[27] > 0 );

        #error_028_table_no_correct_end('');               # get_tables()
        error_029_gallery_no_correct_end() if ( $ErrorPriority[29] > 0 );

        #error_030                                         # DEACTIVATED
        error_031_html_table_element()     if ( $ErrorPriority[31] > 0 );
        error_032_double_pipe_in_link()    if ( $ErrorPriority[32] > 0 );
        error_033_html_element_underline() if ( $ErrorPriority[33] > 0 );
        error_034_template_programming()   if ( $ErrorPriority[34] > 0 );

        #error_035                                         # DEACTIVATED
        error_036_redirect_not_correct() if ( $ErrorPriority[36] > 0 );
        error_037_title_with_special_letter_and_no_defaultsort()
          if ( $ErrorPriority[34] > 0 );
        error_038_html_element_italic()    if ( $ErrorPriority[38] > 0 );
        error_039_html_element_paragraph() if ( $ErrorPriority[39] > 0 );
        error_040_html_element_font()      if ( $ErrorPriority[40] > 0 );
        error_041_html_element_big()       if ( $ErrorPriority[41] > 0 );
        error_042_html_element_strike()    if ( $ErrorPriority[42] > 0 );

        #error_043_template_no_correct_end('');            # get_templates()
        error_044_headline_with_bold()            if ( $ErrorPriority[44] > 0 );
        error_045_interwiki_double()              if ( $ErrorPriority[45] > 0 );
        error_046_count_square_breaks_begin()     if ( $ErrorPriority[46] > 0 );
        error_047_template_no_correct_begin()     if ( $ErrorPriority[47] > 0 );
        error_048_title_in_text()                 if ( $ErrorPriority[48] > 0 );
        error_049_headline_with_html()            if ( $ErrorPriority[49] > 0 );
        error_050_dash()                          if ( $ErrorPriority[50] > 0 );
        error_051_interwiki_before_headline()     if ( $ErrorPriority[51] > 0 );
        error_052_category_before_last_headline() if ( $ErrorPriority[52] > 0 );
        error_053_interwiki_before_category()     if ( $ErrorPriority[53] > 0 );
        error_054_break_in_list()                 if ( $ErrorPriority[54] > 0 );
        error_055_html_element_small_double()     if ( $ErrorPriority[55] > 0 );
        error_056_arrow_as_ASCII_art()            if ( $ErrorPriority[56] > 0 );
        error_057_headline_end_with_colon()       if ( $ErrorPriority[57] > 0 );
        error_058_headline_with_caps()            if ( $ErrorPriority[58] > 0 );
        error_059_template_value_end_br()         if ( $ErrorPriority[59] > 0 );
        error_060_template_parameter_problem()    if ( $ErrorPriority[60] > 0 );
        error_061_reference_with_punctuation()    if ( $ErrorPriority[61] > 0 );
        error_062_url_without_http()              if ( $ErrorPriority[62] > 0 );
        error_063_html_element_small_ref_sub_sup()
          if ( $ErrorPriority[63] > 0 );
        error_064_link_equal_linktext()          if ( $ErrorPriority[64] > 0 );
        error_065_image_description_with_break() if ( $ErrorPriority[65] > 0 );
        error_066_image_description_with_full_small()
          if ( $ErrorPriority[66] > 0 );
        error_067_ref_after_punctuation()  if ( $ErrorPriority[67] > 0 );
        error_068_link_to_other_language() if ( $ErrorPriority[68] > 0 );
        error_069_isbn_wrong_syntax()      if ( $ErrorPriority[69] > 0 );

        #error_070_isbn_wrong_length('');                  # get_isbn()
        #error_071_isbn_wrong_pos_X('');                   # get_isbn()
        #error_072_isbn_10_wrong_checksum('');             # get_isbn()
        #error_073_isbn_13_wrong_checksum('');             # get_isbn()
        error_074_link_with_no_target()      if ( $ErrorPriority[74] > 0 );
        error_075_indented_list()            if ( $ErrorPriority[75] > 0 );
        error_076_link_with_no_space()       if ( $ErrorPriority[76] > 0 );
        error_077_image_with_partial_small() if ( $ErrorPriority[77] > 0 );
        error_078_reference_double()         if ( $ErrorPriority[78] > 0 );

        #error_079                                         # DEACTIVATED
        error_080_externallink_with_line_break() if ( $ErrorPriority[80] > 0 );
        error_081_ref_double()                   if ( $ErrorPriority[81] > 0 );
        error_082_link_to_other_wikiproject()    if ( $ErrorPriority[82] > 0 );
        error_083_headline_begin_level_three()   if ( $ErrorPriority[83] > 0 );
        error_084_section_without_text()         if ( $ErrorPriority[84] > 0 );
        error_085_tag_without_content()          if ( $ErrorPriority[85] > 0 );
        error_086_link_with_double_brackets()    if ( $ErrorPriority[86] > 0 );
        error_087_html_named_entities_without_semicolon()
          if ( $ErrorPriority[87] > 0 );
        error_088_defaultsort_with_first_blank() if ( $ErrorPriority[88] > 0 );
        error_089_defaultsort_with_no_space_after_comma()
          if ( $ErrorPriority[89] > 0 );
        error_090_Internal_link_written_as_external_link()
          if ( $ErrorPriority[90] > 0 );
        error_091_Interwiki_link_written_as_external_link()
          if ( $ErrorPriority[91] > 0 );
        error_092_headline_double()        if ( $ErrorPriority[92] > 0 );
        error_093_double_http()            if ( $ErrorPriority[93] > 0 );
        error_094_ref_no_correct_match()   if ( $ErrorPriority[94] > 0 );
        error_095_user_signature()         if ( $ErrorPriority[95] > 0 );
        error_096_toc_after_1st_headline() if ( $ErrorPriority[96] > 0 );
        error_097_toc_has_material_after() if ( $ErrorPriority[97] > 0 );
        error_098_sub_no_correct_end()     if ( $ErrorPriority[98] > 0 );
        error_099_sup_no_correct_end()     if ( $ErrorPriority[99] > 0 );
        error_100_li_tag_no_correct_end()  if ( $ErrorPriority[100] > 0 );
        error_101_ordinal_numbers_in_sup() if ( $ErrorPriority[101] > 0 );
        error_102_pmid_wrong_syntax()      if ( $ErrorPriority[102] > 0 );
        error_103_pipe_in_wikilink()       if ( $ErrorPriority[103] > 0 );
        error_104_quote_marks_in_refs()    if ( $ErrorPriority[104] > 0 );
        error_105_headline_start_begin()   if ( $ErrorPriority[105] > 0 );
        error_106_issn_wrong_syntax()      if ( $ErrorPriority[106] > 0 );

        #error_107_issn_wrong_length       get_issn
        #error_108_issn_wrong_checksum     get_issn
        error_109_include_tag_error()  if ( $ErrorPriority[109] > 0 );
        error_110_found_include_tag()  if ( $ErrorPriority[110] > 0 );
        error_111_ref_after_ref_list() if ( $ErrorPriority[111] > 0 );
        error_112_css_attribute()      if ( $ErrorPriority[112] > 0 );
    }

    return ();
}

###########################################################################
##  ERROR 01
###########################################################################

sub error_001_word_template {
    my $error_code = 1;

    foreach my $namespace (@Namespace_templates) {
        if ( $lc_text =~ /(\{\{\s*$namespace:)/ ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 02
###########################################################################

sub error_002_have_br {
    my $error_code = 2;

    # CHECK FOR <br> and <hr> issues
    foreach my $regex (@REGEX_BR_002) {
        if ( $lc_text =~ /$regex/ ) {
            my $test_line = substr( $text, $-[0], 40 );
            error_register( $error_code, $test_line );
        }
    }

    # CHECK FOR </center/> or <center/>
    foreach my $regex (@REGEX_002) {
        if ( $lc_text =~ /$regex/ ) {
            my $test_line = substr( $text, $-[0], 40 );
            error_register( $error_code, $test_line );
        }
    }

    # CHECK FOR <ref><cite> due to bug in CX
    if ( $lc_text =~ /<ref><cite>/ ) {
        my $test_line = substr( $text, $-[0], 40 );
        error_register( $error_code, $test_line );
    }

    return ();
}

###########################################################################
## ERROR 03
###########################################################################

sub error_003_have_ref {
    my $error_code = 3;

    if (   index( $lc_text, '<ref>' ) > -1
        or index( $lc_text, '<ref name' ) > -1 )
    {

        my $test      = 'false';
        my $test_text = $lc_text;

        $test = 'true'
          if (  $test_text =~ /<[ ]?+references>/
            and $test_text =~ /<[ ]?+\/references>/ );
        $test = 'true' if ( $test_text =~ /<[ ]?+references[ ]?+\/>/ );
        $test = 'true' if ( $test_text =~ /<[ ]?+references group/ );
        $test = 'true' if ( $test_text =~ /\{\{[ ]?+refbegin/ );
        $test = 'true' if ( $test_text =~ /\{\{[ ]?+refend/ );
        $test = 'true' if ( $test_text =~ /\{\{[ ]?+reflist/ );

        # hrwiki doesn't have a translation file
        if ( $project eq 'hrwiki' ) {
            if ( $test_text =~ /\{\{[ ]?+izvori/ ) {
                $test = 'true';
            }
        }

        if ( $Template_list[$error_code][0] ne '-9999' ) {

            foreach my $regex (@REGEX_003) {
                if ( $test_text =~ /$regex/ ) {
                    $test = 'true';
                    next;
                }
            }
        }
        if ( $test eq 'false' ) {
            error_register( $error_code, q{} );
        }
    }

    return ();
}

###########################################################################
## ERROR 04
###########################################################################

sub error_004_html_element_a {
    my $error_code = 4;

    my $begin = index( $lc_text, '<a ' );
    my $end   = index( $lc_text, '</a>' );

    if ( $begin > -1 ) {
        error_register( $error_code, substr( $text, $begin, 40 ) );
    }
    elsif ( $end > -1 ) {
        error_register( $error_code, substr( $text, $end, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 05
###########################################################################

sub error_005_Comment_no_correct_end {
    my ($comment) = @_;
    my $error_code = 5;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( $comment ne q{} ) {
            error_register( $error_code, substr( $comment, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 06
###########################################################################

sub error_006_defaultsort_special_letter {
    my $error_code = 6;

    # Is DEFAULTSORT found in article?
    my $isDefaultsort = -1;
    foreach (@Magicword_defaultsort) {
        $isDefaultsort = index( $text, $_ ) if ( $isDefaultsort == -1 );
    }

    if ( $isDefaultsort > -1 ) {
        my $pos2 = index( substr( $text, $isDefaultsort ), '}}' );
        my $test_text = substr( $text, $isDefaultsort, $pos2 );

        my $test_text2 = $test_text;

        # Remove ok letters
        $test_text =~ s/[-–:,.\/()!?' \p{XPosixAlpha}\p{XPosixAlnum}]//g;

        # Too many to figure out what is right or not
        $test_text =~ s/#//g;
        $test_text =~ s/\+//g;

        if ( $test_text ne q{} ) {
            $test_text2 = '{{' . $test_text2 . '}}';
            error_register( $error_code, $test_text2 );
        }
    }

    return ();
}

###########################################################################
## ERROR 07
###########################################################################

sub error_007_headline_only_three {
    my $error_code = 7;

    if ( $Headlines[0] ) {

        if ( $Headlines[0] =~ /===/ ) {

            my $found_level_two = 'no';
            foreach my $headline (@Headlines) {
                if ( $headline =~ /^==[^=]/ ) {
                    $found_level_two = 'yes';    #found level two (error 83)
                }
            }
            if ( $found_level_two eq 'no' ) {
                error_register( $error_code, $Headlines[0] );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 08
###########################################################################

sub error_008_headline_start_end {
    my $error_code = 8;

    foreach my $line (@Headlines) {

        if ( $line =~ /^==/
            and not( $line =~ /==\s*$/ ) )
        {
            # Check for cases where a ref is after ==.  Many times a
            # ref is in the heading with a new line in the ref... This
            # is two entries in @Headlines and causes a false positive.
            # Make sure the refs is after the last ==.
            if ( index( $line, '<ref' ) > 0 ) {
                if ( $line =~ /=\s*<ref/ ) {
                    error_register( $error_code, substr( $line, 0, 40 ) );
                }
            }
            else {
                error_register( $error_code, substr( $line, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 09
###########################################################################

sub error_009_multiple_category_in_line {
    my $error_code = 9;

    if ( $text =~
        /\[\[($Cat_regex):(.*?)\]\]([ ]*)\[\[($Cat_regex):(.*?)\]\]/ig )
    {

        my $error_text =
          '[[' . $1 . q{:} . $2 . ']]' . $3 . '[[' . $4 . q{:} . $5 . "]]\n";
        error_register( $error_code, substr( $error_text, 0, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 10
###########################################################################

sub error_010_count_square_breaks {
    my ($comment) = @_;
    my $error_code = 10;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( $comment ne q{} ) {
            error_register( $error_code, substr( $comment, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 11
###########################################################################

sub error_011_html_named_entities {
    my $error_code = 11;
    my $pos        = -1;

    # HTML NAMED ENTITIES ALLOWED IN MATH TAGS
    if ( $lc_text !~ /<math|\{\{math\s*\|/ ) {
        foreach (@HTML_NAMED_ENTITIES_011) {
            if ( $lc_text =~ /&$_;/g ) {
                $pos = $-[0];
            }
        }
    }

    if ( $pos > -1 ) {
        error_register( $error_code, substr( $text, $pos, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 12
###########################################################################

sub error_012_html_list_elements {
    my $error_code = 12;

    if (   index( $lc_text, '<ol>' ) > -1
        or index( $lc_text, '<ul>' ) > -1
        or index( $lc_text, '<li>' ) > -1 )
    {

        # Only search for <ol>. <ol type an <ol start can be used.
        if (    index( $lc_text, '<ol start' ) == -1
            and index( $lc_text, '<ol type' ) == -1
            and index( $lc_text, '<ol reversed' ) == -1 )
        {

            # <ul> or <li> in templates can be only way to do a list.
            my $test_text = $text;
            foreach (@Templates_all) {
                $test_text =~ s/\Q$_\E//s;
            }

            my $test_text_lc = lc($test_text);
            my $pos = index( $test_text_lc, '<ol>' );

            if ( $pos == -1 ) {
                $pos = index( $test_text_lc, '<ul>' );
            }
            if ( $pos == -1 ) {
                $pos = index( $test_text_lc, '<li>' );
            }

            if ( $pos > -1 ) {
                $test_text = substr( $test_text_lc, $pos, 40 );
                error_register( $error_code, $test_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 13
###########################################################################

sub error_013_Math_no_correct_end {
    my ($comment) = @_;
    my $error_code = 13;

    if ( $ErrorPriority[$error_code] > 0 ) {

        if ( $comment ne q{} ) {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 14
###########################################################################

sub error_014_Source_no_correct_end {
    my ($comment) = @_;
    my $error_code = 14;

    if ( $ErrorPriority[$error_code] > 0 ) {

        if ( $comment ne q{} ) {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 15
###########################################################################

sub error_015_Code_no_correct_end {
    my ($comment) = @_;
    my $error_code = 15;

    if ( $ErrorPriority[$error_code] > 0 ) {

        if ( $comment ne q{} ) {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 16
###########################################################################

sub error_016_unicode_control_character {
    my $error_code = 16;

    # 200B is a problem with IPA characters in some wikis (czwiki)
    # \p{Co} or PUA is Private Unicode Area

    if ( $project eq 'enwiki' ) {
        if ( $text =~ /($REGEX_LONG_016)/ or $text =~ /(\p{Co})/ ) {
            my $test_text = $text;
            my $pos = index( $test_text, $1 );
            $test_text = substr( $test_text, $pos, 40 );
            $test_text =~ s/[\p{Co}]/\{PUA\}/;
            $test_text =~ s/\x{007F}/\{007F\}/;
            $test_text =~ s/\x{2004}/\{2004\}/;
            $test_text =~ s/\x{2005}/\{2005\}/;
            $test_text =~ s/\x{2006}/\{2006\}/;
            $test_text =~ s/\x{2007}/\{2007\}/;
            $test_text =~ s/\x{2008}/\{2008\}/;
            $test_text =~ s/\x{200B}/\{200B\}/;
            $test_text =~ s/\x{200E}/\{200E\}/;
            $test_text =~ s/\x{202A}/\{202A\}/;
            $test_text =~ s/\x{2028}/\{2028\}/;
            $test_text =~ s/\x{202C}/\{202C\}/;
            $test_text =~ s/\x{202D}/\{202D\}/;
            $test_text =~ s/\x{202E}/\{202E\}/;
            $test_text =~ s/\x{FEFF}/\{FEFF\}/;
            $test_text =~ s/\x{FFFC}/\{FFFC\}/;
            $test_text =~ s/\x{00A0}/\{00A0\}/;

            error_register( $error_code, $test_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 17
###########################################################################

sub error_017_category_double {
    my $error_code  = 17;
    my $found_error = 0;

    foreach my $i ( 0 .. $Category_counter - 1 ) {
        my $test = $Category[$i][2];

        # Change underscore to space as one cat is ok and duplicate
        # cat is identical except for underscores
        $test =~ tr/_/ /;

        if ( $test ne q{} ) {
            $test = uc( substr( $test, 0, 1 ) ) . substr( $test, 1 );

            foreach my $j ( $i + 1 .. $Category_counter ) {
                my $test2 = $Category[$j][2];
                $test2 =~ tr/_/ /;

                if ( $test2 ne q{} ) {
                    $test2 =
                      uc( substr( $test2, 0, 1 ) ) . substr( $test2, 1 );
                }

                if ( $test eq $test2 ) {
                    if ( $found_error == 0 ) {
                        $found_error++;
                        error_register( $error_code, $Category[$i][2] );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 18
###########################################################################

sub error_018_category_1st_letter_small {
    my $error_code = 18;

        foreach my $i ( 0 .. $Category_counter ) {
            my $test_letter = substr( $Category[$i][2], 0, 1 );
            my $test_cat    = substr( $Category[$i][4], 0, 3 );

            # \p{Ll} is a lowercase letter that has an uppercase variant.
            if ( $test_letter =~ /\p{Ll}/ ) {
                error_register( $error_code, $Category[$i][2] );
            }
            if ( $test_cat eq '[[c' ) {
                error_register( $error_code, $Category[$i][4] );
            }

        }

    return ();
}

###########################################################################
## ERROR 19
###########################################################################

sub error_019_headline_only_one {
    my $error_code = 19;

    foreach my $headline (@Headlines) {
        if ( $headline =~ /^=[^=]/ ) {
            error_register( $error_code, substr( $headline, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 20
###########################################################################

sub error_020_symbol_for_dead {
    my $error_code = 20;

    my $pos = index( $text, '&dagger;' );
    if ( $pos > -1 ) {
        error_register( $error_code, substr( $text, $pos, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 21
###########################################################################

sub error_021_category_is_english {
    my $error_code = 21;

    if ( $Namespace_cat[0] ne 'Category' ) {

        foreach my $i ( 0 .. $Category_counter ) {
            my $current_cat = lc( $Category[$i][4] );

            if ( index( $current_cat, lc( $Namespace_cat[1] ) ) > -1 ) {
                error_register( $error_code, $current_cat );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 22
###########################################################################

sub error_022_category_with_space {
    my $error_code = 22;

    foreach my $i ( 0 .. $Category_counter ) {

        # SOME WIKIS HAVE COLONS IN THEIR CAT NAMES, REMOVE LAST ONE
        my $total = $Category[$i][4] =~ tr/:/:/;
        if ( $total > 1 ) {
            my $last_colon = rindex( $Category[$i][4], q{:} );
            $Category[$i][4] = substr( $Category[$i][4], 0, $last_colon );
        }

        if (   $Category[$i][4] =~ /[^ |]\s+\]\]$/
            or $Category[$i][4] =~ /\[\[ /
            or $Category[$i][4] =~ / \|/
            or $Category[$i][4] =~ /\[\[($Cat_regex)\s+:|:\s+/ )
        {
            error_register( $error_code, $Category[$i][4] );
        }
    }

    return ();
}

###########################################################################
## ERROR 23
###########################################################################

sub error_023_nowiki_no_correct_end {
    my ($comment) = @_;
    my $error_code = 23;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( $comment ne q{} ) {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 24
###########################################################################

sub error_024_pre_no_correct_end {
    my ($comment) = @_;
    my $error_code = 24;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( $comment ne q{} ) {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 25
###########################################################################

sub error_025_headline_hierarchy {
    my $error_code      = 25;
    my $number_headline = -1;
    my $old_headline    = q{};
    my $new_headline    = q{};

    foreach my $headline (@Headlines) {
        $number_headline = $number_headline + 1;
        $old_headline    = $new_headline;
        $new_headline    = $headline;

        if ( $number_headline > 0 ) {
            my $level_old = $old_headline;
            my $level_new = $new_headline;

            $level_old =~ s/^([=]+)//;
            $level_new =~ s/^([=]+)//;
            $level_old = length($old_headline) - length($level_old);
            $level_new = length($new_headline) - length($level_new);

            if ( $level_new > $level_old
                and ( $level_new - $level_old ) > 1 )
            {
                error_register( $error_code,
                    $old_headline . '<br>' . $new_headline );
                last;
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 26
###########################################################################

sub error_026_html_text_style_elements {
    my $error_code = 26;

    my $pos = index( $lc_text, '<b>' );

    if ( $pos > -1 ) {
        error_register( $error_code, substr( $text, $pos, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 27
###########################################################################

sub error_027_unicode_syntax {
    my $error_code = 27;
    my $pos        = -1;

    $pos = index( $text, '&#322;' )   if ( $pos == -1 );    # l in Wrozlaw
    $pos = index( $text, '&#x0124;' ) if ( $pos == -1 );    # l in Wrozlaw
    $pos = index( $text, '&#8211;' )  if ( $pos == -1 );    # –

    if ( $pos > -1 ) {
        error_register( $error_code, substr( $text, $pos, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 28
###########################################################################

sub error_028_table_no_correct_end {
    my ($comment) = @_;
    my $error_code = 28;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( $comment ne q{} ) {

            my $test = 'false';

            if ( $Template_list[$error_code][0] ne '-9999' ) {

                my @codes = @{ $Template_list[$error_code] };

                foreach my $temp (@codes) {
                    if ( index( $lc_text, $temp ) > -1 ) {
                        $test = 'true';
                    }
                }
            }
            if ( $test eq 'false' ) {
                error_register( $error_code, $comment );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 29
###########################################################################

sub error_029_gallery_no_correct_end {
    my $error_code    = 29;
    my $gallery_begin = () = $lc_text =~ /<gallery/g;
    my $gallery_end   = () = $lc_text =~ /<\/gallery>/g;

    if ( $gallery_begin != $gallery_end ) {
        if ( $gallery_begin > $gallery_end ) {
            my $snippet = get_broken_tag( '<gallery', '</gallery>' );
            error_register( $error_code, $snippet );
        }
        else {
            my $snippet = get_broken_tag_closing( '<gallery', '</gallery>' );
            error_register( $error_code, $snippet );
        }
    }

    return ();
}

###########################################################################
## ERROR 31
###########################################################################

sub error_031_html_table_element {
    my $error_code = 31;

    if ( index( $lc_text, '<table' ) > -1 ) {

        # <table> in templates can be the only way to do a table.
        my $test_text = $text;
        foreach (@Templates_all) {
            $test_text =~ s/\Q$_\E//s;
        }

        my $test_text_lc = lc($test_text);
        my $pos = index( $test_text_lc, '<table' );

        if ( $pos > -1 ) {
            $test_text = substr( $test_text_lc, $pos, 40 );
            error_register( $error_code, $test_text );
        }
    }
    elsif ( index( $lc_text, '<tr' ) > -1 ) {

        # <tr> in templates can be the only way to do a table.
        my $test_text = $text;
        foreach (@Templates_all) {
            $test_text =~ s/\Q$_\E//s;
        }

        my $test_text_lc = lc($test_text);
        my $pos = index( $test_text_lc, '<tr' );

        if ( $pos > -1 ) {
            $test_text = substr( $test_text_lc, $pos, 40 );
            error_register( $error_code, $test_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 32
###########################################################################

sub error_032_double_pipe_in_link {
    my $error_code = 32;

    foreach my $line (@Lines) {
        if ( $line =~ /\[\[[^\]:\{]+\|([^\]\{]+\||\|)/g ) {
            my $first_part = substr( $line, 0, pos($line) );
            my $second_part = substr( $line, pos($line) );
            my @first_part_split = split( /\[\[/, $first_part );
            foreach (@first_part_split) {
                $first_part = '[[' . $_;    # Find last link in first_part
            }
            my $current_line = $first_part . $second_part;
            error_register( $error_code, substr( $current_line, 0, 40 ) );
            last;
        }
    }

    return ();
}

###########################################################################
## ERROR 33
###########################################################################

sub error_033_html_element_underline {
    my $error_code = 33;

    my $pos = index( $lc_text, '<u>' );

    if ( $pos > -1 ) {
        error_register( $error_code, substr( $text, $pos, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 34
###########################################################################

sub error_034_template_programming {
    my $error_code = 34;
    my $found      = 0;

    if (    $project ne 'ukwiki'
        and $project ne 'ruwiki'
        and $project ne 'bewiki' )
    {
        foreach my $regex (@REGEX_034_BRACKET) {
            if ( $lc_text =~ /$regex/ ) {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
                $found = 1;
                last;
            }
        }
    }
    else {
        foreach my $regex (@REGEX_034) {
            if ( $lc_text =~ /$regex/ ) {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
                $found = 1;
                last;
            }
        }
    }

    if ( $Template_list[$error_code][0] ne '-9999' and $found = 0 ) {

        my @codes = @{ $Template_list[$error_code] };

        foreach my $temp (@codes) {

            if ( $temp =~ /^__/ ) {
                if ( $text =~ /($temp)/ ) {
                    my $test_line = substr( $text, $-[0], 40 );
                    $test_line =~ s/[\n\r]//mg;
                    error_register( $error_code, $test_line );
                    last;
                }
            }
            else {
                if ( $text =~ /\{\{($temp)/ ) {
                    my $test_line = substr( $text, $-[0], 40 );
                    $test_line =~ s/[\n\r]//mg;
                    error_register( $error_code, $test_line );
                    last;
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 36
###########################################################################

sub error_036_redirect_not_correct {
    my $error_code = 36;

    if ( $page_is_redirect eq 'yes' ) {
        if ( $lc_text =~ /#redirect[ ]?+[^ :[][ ]?+\[/ ) {
            error_register( $error_code, substr( $text, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 37
###########################################################################

sub error_037_title_with_special_letter_and_no_defaultsort {
    my $error_code = 37;

    if ( $Category_counter > -1 and length($title) > 2 ) {

        # Is DEFAULTSORT found in article?
        my $isDefaultsort = -1;
        foreach (@Magicword_defaultsort) {
            $isDefaultsort = index( $text, $_ ) if ( $isDefaultsort == -1 );
        }

        if ( $isDefaultsort == -1 ) {

            my $test_title = $title;
            if ( $project ne 'enwiki' ) {
                $test_title = substr( $test_title, 0, 5 );
            }

            # Remove ok letters
            $test_title =~ s/[-–:,.\/()!?' \p{XPosixAlpha}\p{XPosixAlnum}]//g;

            # Too many to figure out what is right or not
            $test_title =~ s/#//g;
            $test_title =~ s/\+//g;

            if ( $test_title ne q{} ) {
                error_register( $error_code, q{} );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 38
###########################################################################

sub error_038_html_element_italic {
    my $error_code = 38;

    my $pos = index( $lc_text, '<i>' );

    if ( $pos > -1 ) {
        error_register( $error_code, substr( $text, $pos, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 39
###########################################################################

sub error_039_html_element_paragraph {
    my $error_code = 39;

    if ( $lc_text =~ /<p>|<p / ) {
        my $test_text = $lc_text;

        # <P> ARE STILL NEEDED IN <REF>
        $test_text =~ s/<ref(.*?)<\/ref>//sg;

        my $pos = index( $test_text, '<p>' );
        if ( $pos > -1 ) {
            error_register( $error_code, substr( $test_text, $pos, 40 ) );
        }
        $pos = index( $test_text, '<p ' );
        if ( $pos > -1 ) {
            error_register( $error_code, substr( $test_text, $pos, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 40
###########################################################################

sub error_040_html_element_font {
    my $error_code = 40;

    my $pos = index( $lc_text, '<font' );

    if ( $pos > -1 ) {
        error_register( $error_code, substr( $text, $pos, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 41
###########################################################################

sub error_041_html_element_big {
    my $error_code = 41;

    my $pos = index( $lc_text, '<big>' );

    if ( $pos > -1 ) {
        error_register( $error_code, substr( $text, $pos, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 42
###########################################################################

sub error_042_html_element_strike {
    my $error_code = 42;

    my $pos = index( $lc_text, '<strike>' );

    if ( $pos > -1 ) {
        error_register( $error_code, substr( $text, $pos, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 43
###########################################################################

sub error_043_template_no_correct_end {
    my ($comment) = @_;
    my $error_code = 43;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( $comment ne q{} ) {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 44
###########################################################################

sub error_044_headline_with_bold {
    my $error_code = 44;

    foreach my $headline (@Headlines) {

        if ( index( $headline, q{'''} ) > -1
            and not $headline =~ /[^']''[^']/ )
        {

            if ( index( $headline, '<ref' ) < 0 ) {
                error_register( $error_code, substr( $headline, 0, 40 ) );
                last;
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 45
###########################################################################

sub error_045_interwiki_double {
    my $error_code = 45;

    my $found_double = q{};
    foreach my $i ( 0 .. $Interwiki_counter ) {

        for ( my $j = $i + 1 ; $j <= $Interwiki_counter ; $j++ ) {
            if ( lc( $Interwiki[$i][5] ) eq lc( $Interwiki[$j][5] ) ) {
                my $test1 = lc( $Interwiki[$i][2] );
                my $test2 = lc( $Interwiki[$j][2] );

                if ( $test1 eq $test2 ) {
                    $found_double =
                      $Interwiki[$i][4] . '<br>' . $Interwiki[$j][4];
                }

            }
        }
    }
    if ( $found_double ne q{} ) {
        error_register( $error_code, $found_double );
    }

    return ();
}

###########################################################################
## ERROR 46
###########################################################################

sub error_046_count_square_breaks_begin {
    my $error_code    = 46;
    my $test_text     = $text;
    my $test_text_1_a = $test_text;
    my $test_text_1_b = $test_text;

    if ( ( $test_text_1_a =~ s/\[\[//g ) != ( $test_text_1_b =~ s/\]\]//g ) ) {
        my $found_text = q{};
        my $begin_time = time();
        while ( $test_text =~ /\]\]/g ) {

            # Begin of link
            my $pos_end                = pos($test_text) - 2;
            my $link_text              = substr( $test_text, 0, $pos_end );
            my $link_text_2            = q{};
            my $beginn_square_brackets = 0;
            my $end_square_brackets    = 1;
            while ( $link_text =~ /\[\[/g ) {

                # Find currect end - number of [[==]]
                my $pos_start = pos($link_text);
                $link_text_2 = substr( $link_text, $pos_start );
                $link_text_2 = q{ } . $link_text_2 . q{ };

                # Test the number of [[and  ]]
                my $link_text_2_a = $link_text_2;
                $beginn_square_brackets = ( $link_text_2_a =~ s/\[\[//g );
                my $link_text_2_b = $link_text_2;
                $end_square_brackets = ( $link_text_2_b =~ s/\]\]//g );

                last
                  if ( $beginn_square_brackets eq $end_square_brackets
                    or $begin_time + 60 > time() );

            }

            if ( $beginn_square_brackets != $end_square_brackets ) {

                # Link has no correct begin
                $found_text = $link_text;
                $found_text =~ s/  / /g;
                $found_text = text_reduce_to_end( $found_text, 50 ) . ']]';
            }

            # End if a problem was found, no endless run
            last if ( $found_text ne q{} or $begin_time + 60 > time() );
        }

        if ( $found_text ne q{} ) {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 47
###########################################################################

sub error_047_template_no_correct_begin {
    my $error_code       = 47;
    my $tag_open         = '{{';
    my $tag_close        = '}}';
    my $look_ahead_open  = 0;
    my $look_ahead_close = 0;
    my $look_ahead       = 0;

    my $tag_open_num  = () = $text =~ /\{\{/g;
    my $tag_close_num = () = $text =~ /}}/g;

    my $diff = $tag_close_num - $tag_open_num;

    if ( $diff > 0 ) {

        my $pos_open   = rindex( $text, $tag_open );
        my $pos_close  = rindex( $text, $tag_close );
        my $pos_close2 = rindex( $text, $tag_close, $pos_open - 2 );

        while ( $diff > 0 ) {
            if ( $pos_close2 == -1 ) {
                error_register( $error_code, substr( $text, $pos_close, 40 ) );
                $diff = -1;
            }
            elsif ( $pos_close2 > $pos_open and $look_ahead < 0 ) {
                error_register( $error_code, substr( $text, $pos_close, 40 ) );
                $diff--;
            }
            else {
                $pos_close  = $pos_close2;
                $pos_close2 = rindex( $text, $tag_close, $pos_close - 2 );
                $pos_open   = rindex( $text, $tag_open, $pos_open - 2 );
                if ( $pos_close2 > 0 ) {
                    $look_ahead_close =
                      rindex( $text, $tag_close, $pos_close2 - 2 );
                    $look_ahead_open =
                      rindex( $text, $tag_open, $pos_open - 2 );
                    $look_ahead = $look_ahead_open - $look_ahead_close;
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 48
###########################################################################

sub error_048_title_in_text {
    my $error_code = 48;
    my $test_text  = $text;

    # OK (MUST) TO HAVE IN IMAGEMAPS, INCLUDEONLY AND TIMELINE
    $test_text =~ s/<imagemap>(.*?)<\/imagemap>//sg;
    $test_text =~ s/<includeonly>(.*?)<\/includeonly>//sg;
    $test_text =~ s/<timeline>(.*?)<\/timeline>//sg;

    $test_text =~ tr/_/ /;

    # [[foo --> [[Foo
    $test_text =~ s/\[\[\s*(\p{Lowercase_Letter})/\[\[\u$1/g;

    # \Q \E makes any meta charachter in title safe (|.*+)
    if ( $test_text =~ /\[\[\s*\Q$title\E\s*(\]\]|\|)/ ) {
        my $test_line = substr( $test_text, $-[0], 40 );
        error_register( $error_code, $test_line );
    }

    return ();
}

###########################################################################
## ERROR 49
###########################################################################

sub error_049_headline_with_html {
    my $error_code = 49;
    my $pos        = -1;

    $pos = index( $lc_text, '<h1>' )  if ( $pos == -1 );
    $pos = index( $lc_text, '<h2>' )  if ( $pos == -1 );
    $pos = index( $lc_text, '<h3>' )  if ( $pos == -1 );
    $pos = index( $lc_text, '<h4>' )  if ( $pos == -1 );
    $pos = index( $lc_text, '<h5>' )  if ( $pos == -1 );
    $pos = index( $lc_text, '<h6>' )  if ( $pos == -1 );
    $pos = index( $lc_text, '</h1>' ) if ( $pos == -1 );
    $pos = index( $lc_text, '</h2>' ) if ( $pos == -1 );
    $pos = index( $lc_text, '</h3>' ) if ( $pos == -1 );
    $pos = index( $lc_text, '</h4>' ) if ( $pos == -1 );
    $pos = index( $lc_text, '</h5>' ) if ( $pos == -1 );
    $pos = index( $lc_text, '</h6>' ) if ( $pos == -1 );
    if ( $pos != -1 ) {
        my $test_text = substr( $text, $pos, 40 );
        $test_text =~ s/\n//g;
        error_register( $error_code, $test_text );
    }

    return ();
}

###########################################################################
## ERROR 50
###########################################################################

sub error_050_dash {
    my $error_code = 50;

    my $pos = -1;
    $pos = index( $lc_text, '&ndash;' );
    $pos = index( $lc_text, '&mdash;' ) if $pos == -1;

    if ( $pos > -1
        and ( $page_namespace == 0 or $page_namespace == 104 ) )
    {
        my $found_text = substr( $text, $pos, 40 );
        $found_text =~ s/\n//g;
        error_register( $error_code, $found_text );
    }

    return ();
}

###########################################################################
## ERROR 51
###########################################################################

sub error_051_interwiki_before_headline {
    my $error_code          = 51;
    my $number_of_headlines = @Headlines;
    my $pos                 = -1;

    if ( $number_of_headlines > 0 ) {
        $pos = index( $text, $Headlines[ $number_of_headlines - 1 ] );

        #pos of last headline

        my $found_text = q{};
        if ( $pos > -1 ) {
            foreach my $i ( 0 .. $Interwiki_counter ) {
                if ( $pos > $Interwiki[$i][0] ) {
                    $found_text = $Interwiki[$i][4];
                }
            }
        }
        if ( $found_text ne q{} ) {
            error_register( $error_code, substr( $found_text, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 52
###########################################################################

sub error_052_category_before_last_headline {
    my $error_code          = 52;
    my $number_of_headlines = @Headlines;
    my $pos                 = -1;

    if ( $number_of_headlines > 0 ) {

        #Position of last headline
        $pos = index( $text, $Headlines[ $number_of_headlines - 2 ] );
    }
    if ( $pos > -1
        and ( $page_namespace == 0 or $page_namespace == 104 ) )
    {
        my $found_text = q{};
        foreach my $count ( 0 .. $Category_counter ) {
            if ( $pos > $Category[$count][0] ) {
                $found_text = $Category[$count][4];
            }
        }

        if ( $found_text ne q{} ) {
            error_register( $error_code, substr( $found_text, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 53
###########################################################################

sub error_053_interwiki_before_category {
    my $error_code = 53;

    if ( $Category_counter > -1 and $Interwiki_counter > -1 ) {

        my $pos_interwiki = $Interwiki[0][0];
        my $found_text    = $Interwiki[0][4];
        foreach my $i ( 0 .. $Interwiki_counter ) {
            if ( $Interwiki[$i][0] < $pos_interwiki ) {
                $pos_interwiki = $Interwiki[$i][0];
                $found_text    = $Interwiki[$i][4];
            }
        }

        my $found = 'false';
        foreach my $i ( 0 .. $Category_counter ) {
            $found = 'true' if ( $pos_interwiki < $Category[$i][0] );
        }

        if ( $found eq 'true' ) {
            error_register( $error_code, $found_text );
        }

    }

    return ();
}

###########################################################################
## ERROR 54
###########################################################################

sub error_054_break_in_list {
    my $error_code = 54;

    foreach my $line (@Lines) {

        if ( index( $line, q{*} ) == 0 ) {
            if ( $line =~ /<br([ ]+)?(\/)?([ ]+)?>([ \t]+)?$/i ) {
                error_register( $error_code, substr( $line, 0, 40 ) );
                last;
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 55
###########################################################################

sub error_055_html_element_small_double {
    my $error_code = 55;

    if ( index( $lc_text, '<small>' ) > -1 ) {

        if ( $lc_text =~ /\<small\>\s*\<small\>|\<\/small\>\s*\<\/small\>/ ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 56
###########################################################################

sub error_056_arrow_as_ASCII_art {
    my $error_code = 56;
    my $pos        = -1;

    $pos = index( $lc_text, '->' );
    $pos = index( $lc_text, '<-' ) if $pos == -1;
    $pos = index( $lc_text, '<=' ) if $pos == -1;
    $pos = index( $lc_text, '=>' ) if $pos == -1;

    if ( $pos > -1 ) {
        my $test_text = substr( $text, $pos - 10, 40 );
        $test_text =~ s/\n//g;
        error_register( $error_code, $test_text );
    }

    return ();
}

###########################################################################
## ERROR 57
###########################################################################

sub error_057_headline_end_with_colon {
    my $error_code = 57;

    foreach my $headline (@Headlines) {
        if ( $headline =~ /:[ ]?[ ]?[ ]?[=]+([ ]+)?$/ ) {
            error_register( $error_code, substr( $headline, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 58
###########################################################################

sub error_058_headline_with_caps {
    my $error_code = 58;

    foreach my $headline (@Headlines) {

        my $headline_nospaces =
          $headline =~ s/[^\p{Uppercase}\p{Lowercase},&]//gr;

        if ( length($headline_nospaces) > 10 ) {

            if ( $headline eq uc $headline ) {
                error_register( $error_code, substr( $headline, 0, 40 ) );
                last;
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 59
###########################################################################

sub error_059_template_value_end_br {
    my $error_code = 59;
    my $found_text = q{};

    foreach my $i ( 0 .. $Number_of_template_parts ) {

        if ( $Template[$i][4] =~ /<br\s*\/?>\s*$/o ) {
            if (    $found_text eq q{}
                and $Template[$i][1] !~ /marriage/i
                and $Template[$i][1] !~ /nihongo/i )
            {
                $found_text = $Template[$i][3] . '=...'
                  . text_reduce_to_end( $Template[$i][4], 20 );
            }
        }
    }
    if ( $found_text ne q{} ) {
        error_register( $error_code, $found_text );
    }

    return ();
}

###########################################################################
## ERROR 60
###########################################################################

sub error_060_template_parameter_problem {
    my $error_code = 60;

    foreach my $i ( 0 .. $Number_of_template_parts ) {

        if ( $Template[$i][3] =~ /[[\]*]|\|:/ ) {
            my $found_text = $Template[$i][1] . ', ' . $Template[$i][3];
            error_register( $error_code, $found_text );
            last;
        }
    }

    return ();
}

###########################################################################
## ERROR 61
###########################################################################

sub error_061_reference_with_punctuation {
    my $error_code = 61;
    my $pos        = -1;

    # Not sure about elipse (...).  "{1,2}[^\.]" to not check for them
    # Space after !, otherwise will catch false-poistive from tables
    if ( $lc_text =~ /<\/ref>[ ]{0,2}(\.{1,2}[^.]|[,?:;]|! )/ ) {
        error_register( $error_code, substr( $text, $-[0], 40 ) );
    }
    elsif ( $lc_text =~ /(<ref name[^\/]*\/>[ ]{0,2}(\.{1,2}[^.]|[,?:;]|! ))/ )
    {
        error_register( $error_code, substr( $text, $-[0], 40 ) );
    }
    elsif ( $Template_list[$error_code][0] ne '-9999' ) {

        foreach my $regex (@REGEX_061) {
            if ( $lc_text =~ /$regex/ ) {
                if ( $pos == -1 ) {
                    $pos = $-[0];
                }
            }
        }
        if ( $pos > -1 ) {
            error_register( $error_code, substr( $text, $pos, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 62
###########################################################################

sub error_062_url_without_http {
    my $error_code = 62;

    if (
        $lc_text =~ /(<ref\b[^<>]*>\s*\[?www\w*\.)(?![^<>[\]{|}]*\[\w*:?\/\/)/ )
    {
        error_register( $error_code, substr( $text, $-[0], 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 63
###########################################################################

sub error_063_html_element_small_ref_sub_sup {
    my $error_code = 63;
    my $pos        = -1;

    if ( index( $lc_text, '<small>' ) > -1 ) {
        $pos = index( $lc_text, '</small></ref>' )  if ( $pos == -1 );
        $pos = index( $lc_text, '</small> </ref>' ) if ( $pos == -1 );
        $pos = index( $lc_text, '<sub><small>' )    if ( $pos == -1 );
        $pos = index( $lc_text, '<sub> <small>' )   if ( $pos == -1 );
        $pos = index( $lc_text, '<sup><small>' )    if ( $pos == -1 );
        $pos = index( $lc_text, '<sup> <small>' )   if ( $pos == -1 );
        $pos = index( $lc_text, '<small><ref' )     if ( $pos == -1 );
        $pos = index( $lc_text, '<small> <ref' )    if ( $pos == -1 );
        $pos = index( $lc_text, '<small><sub>' )    if ( $pos == -1 );
        $pos = index( $lc_text, '<small> <sub>' )   if ( $pos == -1 );

        #$pos = index( $lc_text, '<small><sup>' )  if ( $pos == -1 );
        #$pos = index( $lc_text, '<small> <sup>' ) if ( $pos == -1 );

        if ( $pos > -1 ) {
            error_register( $error_code, substr( $text, $pos, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 64
###########################################################################

sub error_064_link_equal_linktext {
    my $error_code = 64;
    my $temp_text  = $text;

    # OK (MUST) TO HAVE IN TIMELINE
    $temp_text =~ s/<timeline>(.*?)<\/timeline>//sg;

    # Account for [[foo_foo|foo foo]] by removing all _.
    $temp_text =~ tr/_/ /;

    # Account for [[Foo|foo]] and [[foo|Foo]] by capitalizing the
    # the first character after the [ and |.  But, do only on
    # non-wiktionary projects
    if ( $project !~ /wiktionary/ ) {

        # [[foo --> [[Foo
        $temp_text =~ s/\[\[\s*(\p{Lowercase_Letter})/\[\[\u$1/g;

        # [[Foo|foo]] --> [[Foo|Foo]]
        $temp_text =~
          s/\[\[([^|\]]*)\s*\|\s*(\p{Lowercase_Letter})/\[\[$1\|\u$2/g;

        # [[Foo|"foo"]] --> [[Foo|''Foo'']]
        $temp_text =~
s/\[\[([^|\]]*)\|([$CHARACTERS_064]+)\s*(\p{Lowercase_Letter})/\[\[$1\|$2\u$3/og;
    }

    # Account for [[Foo|Foo]]
    if ( $temp_text =~ /(\[\[([^|]*)\|\2\s*\]\])/ ) {
        my $found_text = $1;
        error_register( $error_code, $found_text );
    }

    # Account for [[Foo|''Foo]]
    elsif ( $temp_text =~ /(\[\[([^\|]*)\|[$CHARACTERS_064]+\2\s*\]\])/o ) {
        my $found_text = $1;
        error_register( $error_code, $found_text );
    }

    # Account for [[Foo|''Foo'']] & [[Foo|Foo'']]
    elsif ( $temp_text =~
        /(\[\[([^|]*)\|([$CHARACTERS_064]+)?\2\s*[$CHARACTERS_064]+\s*\]\])/o )
    {
        my $found_text = $1;
        if ( $found_text !~ /\[\[([^|]*)\|\1\s*'+\s*\]\]/ ) {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 65
###########################################################################

sub error_065_image_description_with_break {
    my $error_code = 65;
    my $found_text = q{};

    foreach my $image (@Images_all) {

        if ( $image =~ /<br([ ]+)?(\/)?([ ]+)?>([ ])?([|\]])/i ) {
            if ( $found_text eq q{} ) {
                $found_text = $image;
            }
        }
    }
    if ( $found_text ne q{} ) {
        error_register( $error_code, $found_text );
    }

    return ();
}

###########################################################################
## ERROR 66
###########################################################################

sub error_066_image_description_with_full_small {
    my $error_code = 66;
    my $found_text = q{};

    foreach my $image (@Images_all) {

        if (    $image =~ /<small([ ]+)?(\/)?([ ]+)?>([ ])?([}\]])/i
            and $image =~ /\|([ ]+)?<small/i )
        {
            if ( $found_text eq q{} ) {
                $found_text = $image;
            }
        }
    }
    if ( $found_text ne q{} ) {
        error_register( $error_code, $found_text );
    }

    return ();
}

###########################################################################
## ERROR 67
###########################################################################

sub error_067_ref_after_punctuation {
    my $error_code = 67;

    my $test_text = lc($text);
    if ( $Template_list[$error_code][0] ne '-9999' ) {

        my @codes = @{ $Template_list[$error_code] };

        foreach my $temp (@codes) {
            $test_text =~ s/${temp}\s*<ref[ >]//sg;
        }

        if ( $test_text =~ /[ ]{0,2}([\.,\?:!;])[ ]{0,2}<ref[ >]/ ) {
            error_register( $error_code, substr( $test_text, $-[0], 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 68
###########################################################################

sub error_068_link_to_other_language {
    my $error_code = 68;

    foreach my $link (@Links_all) {

        foreach (@INTER_LIST) {
            if ( $link =~ /^\[\[([ ]+)?:([ ]+)?$_:/i ) {
                error_register( $error_code, $link );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 69
###########################################################################

sub error_069_isbn_wrong_syntax {
    my $error_code = 69;

    if (
            index( $text, 'ISBN' ) > 0
        and $title ne 'International Standard Book Number'
        and $title ne 'ISBN'
        and $title ne 'ISBN-10'
        and $title ne 'ISBN-13'
        and $title ne 'Internationaal Standaard Boeknummer'
        and $title ne 'International Standard Book Number'
        and $title ne 'European Article Number'
        and $title ne 'Internationale Standardbuchnummer'
        and $title ne 'Buchland'
        and $title ne 'Codice ISBN'
        and index( $title, 'ISBN' ) == -1

      )
    {

        if ( $text =~ / ISBN\s*(?:[-:#;]|10|13)\s*/g ) {

            # Use "-2" to see if there is a | before ISBN
            # in the next if statement
            my $output = substr( $text, $-[0] - 2, 40 );
            my $error  = substr( $text, $-[0],     40 );

            # INFOBOXES AND TEMPLATES CAN HAVE "| ISBN10 = ".
            # ALSO DON'T CHECK ISBN (10|13)XXXXXXXXXX
            if (    ( $output !~ /\|\s*ISBN(?:10|13)\s*=/g )
                and ( $output !~ /ISBN\s*[-:#;]*\s*(?:10|13)\d/g ) )
            {
                error_register( $error_code, $error );
            }
        }
        elsif ( $text =~ / \[\[ISBN\]\]\s*[-:#;]+\s*\d/g ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }

        # CHECK FOR CASES OF ISBNXXXXXXXXX.  INFOBOXES CAN HAVE ISBN10
        # SO NEED TO WORK AROUND THAT.
        elsif ( $text =~ / ISBN\d[-\d ][-\d]/g ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }
        elsif ( $text =~ / (10|13)-ISBN/g ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }

        # <nowiki>ISBN 0123456789</nowiki>
        elsif ( $text =~ /<nowiki>\s*ISBN\s*[ 0-9-xX]*<\/nowiki>/ ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }

        # [[ISBN 0123456789]]
        elsif ( $text =~ /\[\[\s*ISBN\s*[0-9-xX]+\]\]/ ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }

        # [http:// ... ISBN 0123456789 ... ]
        elsif ( $text =~ /\[https?:\/\/[^\]]*(ISBN \d[^\]]*\])/ ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }
        elsif ( $text =~ /ISBN\.\s*\d/ ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }

    }

    return ();
}

###########################################################################
## ERROR 70
###########################################################################

sub error_070_isbn_wrong_length {
    my ($found_text) = @_;
    my $error_code = 70;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne q{} )
        {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 71
###########################################################################

sub error_071_isbn_wrong_pos_X {
    my ($found_text) = @_;
    my $error_code = 71;

    if ( $ErrorPriority[$error_code] > 0 ) {

        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne q{} )
        {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 71
###########################################################################

sub error_072_isbn_10_wrong_checksum {
    my ($found_text) = @_;
    my $error_code = 72;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne q{} )
        {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 73
###########################################################################

sub error_073_isbn_13_wrong_checksum {
    my ($found_text) = @_;
    my $error_code = 73;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne q{} )
        {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 74
###########################################################################

sub error_074_link_with_no_target {
    my $error_code = 74;

    foreach my $link (@Links_all) {
        if ( index( $link, '[[|' ) > -1 ) {
            my $pos = index( $link, '[[|' );
            error_register( $error_code, substr( $link, $pos, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 75
###########################################################################

sub error_075_indented_list {
    my $error_code = 75;

    if ( $text =~ /[:*]/ or $text =~ /:#/ ) {

        my $list = 0;

        foreach my $line (@Lines) {

            if ( index( $line, q{*} ) == 0 or index( $line, q{#} ) == 0 ) {
                $list = 1;
            }
            elsif ( $list == 1
                and ( $line ne q{} and index( $line, q{:} ) != 0 ) )
            {
                $list = 0;
            }

            if ( $list == 1
                and
                ( index( $line, q{:*} ) == 0 or index( $line, q{:#} ) == 0 ) )
            {
                error_register( $error_code, substr( $line, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 76
###########################################################################

sub error_076_link_with_no_space {
    my $error_code = 76;

    foreach my $link (@Links_all) {

        if ( $link =~ /^\[\[([^|]+)%20([^|]+)/ ) {
            error_register( $error_code, $link );
        }
    }

    return ();
}

###########################################################################
## ERROR 77
###########################################################################

sub error_077_image_with_partial_small {
    my $error_code = 77;

    foreach my $image (@Images_all) {

        if ( $image =~ /<small([ ]+)?([\/\\])?([ ]+)?>([ ])?/i
            and not $image =~ /\|([ ]+)?<([ ]+)?small/ )
        {
            error_register( $error_code, $image );
        }
    }

    return ();
}

###########################################################################
## ERROR 78
###########################################################################

sub error_078_reference_double {
    my $error_code = 78;

    my $number_of_refs = 0;
    $number_of_refs = () = $lc_text =~ /<references[ ]?\/?>/g;

    if ( $Template_list[$error_code][0] ne '-9999' ) {
        foreach my $regex (@REGEX_078) {
            $number_of_refs += () = $lc_text =~ /$regex/g;
        }

    }
    if ( $number_of_refs > 1 ) {
        error_register( $error_code, q{} );
    }

    return ();
}

###########################################################################
## ERROR 80
###########################################################################

sub error_080_externallink_with_line_break {
    my $error_code    = 80;
    my $pos_start_old = 0;
    my $end_search    = 0;

    while ( $end_search == 0 ) {
        my $pos_start   = 0;
        my $pos_start_s = 0;
        my $pos_end     = 0;
        $end_search = 1;

        $pos_start   = index( $lc_text, '[http://',  $pos_start_old );
        $pos_start_s = index( $lc_text, '[https://', $pos_start_old );
        if ( ( $pos_start_s < $pos_start ) and ( $pos_start_s > -1 ) ) {
            $pos_start = $pos_start_s;
        }
        $pos_end = index( $lc_text, ']', $pos_start );

        if ( $pos_start > -1 and $pos_end > -1 ) {

            $end_search    = 0;
            $pos_start_old = $pos_end;

            my $weblink = substr( $lc_text, $pos_start, $pos_end - $pos_start );

            if ( $weblink =~ /\n/ ) {
                error_register( $error_code, substr( $weblink, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 81
###########################################################################

sub error_081_ref_double {
    my $error_code    = 81;
    my $number_of_ref = @Ref;

    foreach my $i ( 0 .. $number_of_ref - 2 ) {

        foreach my $j ( $i + 1 .. $number_of_ref - 1 ) {

            if ( $Ref[$i] eq $Ref[$j] ) {
                error_register( $error_code, substr( $Ref[$i], 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 82
###########################################################################

sub error_082_link_to_other_wikiproject {
    my $error_code = 82;

    foreach my $current_link (@Links_all) {

        foreach my $project (@FOUNDATION_PROJECTS) {
            if (   $current_link =~ /^\[\[([ ]+)?$project:/i
                or $current_link =~ /^\[\[([ ]+)?:([ ]+)?$project:/i )
            {
                error_register( $error_code, $current_link );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 83
###########################################################################

sub error_083_headline_begin_level_three {
    my $error_code = 83;

    if ( $Headlines[0] ) {

        if ( $Headlines[0] =~ /===/ ) {

            my $found_level_two = 'no';
            foreach my $headline (@Headlines) {
                if ( $headline =~ /^==[^=]/ ) {
                    $found_level_two = 'yes';    #found level two (error 83)
                }
            }
            if ( $found_level_two eq 'yes' ) {
                error_register( $error_code, $Headlines[0] );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 84
###########################################################################

sub error_084_section_without_text {
    my $error_code = 84;

    if ( $Headlines[0] ) {

        my $section_text = q{};
        my @my_lines = split( /\n/, $text_original );
        my @my_headlines;
        my @my_section;

        foreach my $current_line (@my_lines) {

            if (    ( substr( $current_line, 0, 1 ) eq q{=} )
                and ( $text =~ /\Q$current_line\E/ ) )
            {
                push( @my_section, $section_text );
                $section_text = q{};
                push( @my_headlines, $current_line );
            }
            $section_text = $section_text . $current_line . "\n";
        }
        push( @my_section, $section_text );

        my $number_of_headlines = @my_headlines;

        foreach my $i ( 0 .. $number_of_headlines - 2 ) {

            # Check level of headline and next headline

            my $level_one = $my_headlines[$i];
            my $level_two = $my_headlines[ $i + 1 ];

            $level_one =~ s/^([=]+)//;
            $level_two =~ s/^([=]+)//;
            $level_one = length( $my_headlines[$i] ) - length($level_one);
            $level_two =
              length( $my_headlines[ $i + 1 ] ) - length($level_two);

            # If headline's level is identical or lower to next headline
            # And headline's level is ==
            if ( $level_one >= $level_two and $level_one == 2 ) {
                if ( $my_section[$i] ) {
                    my $test_section  = $my_section[ $i + 1 ];
                    my $test_headline = $my_headlines[$i];
                    $test_headline =~ s/\n//g;

                    $test_section =
                      substr( $test_section, length($test_headline) )
                      if ($test_section);

                    if ($test_section) {
                        $test_section =~ s/\s//g;
                        $test_headline =~ s/=//g;
                        $test_headline =~ s/\s//g;

                        my $length = length($test_headline);
                        if ( $length > 1 and $test_section eq q{} ) {
                            error_register( $error_code, $my_headlines[$i] );
                        }
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 85
###########################################################################

sub error_085_tag_without_content {
    my $error_code = 85;

    foreach (@REGEX_085) {
        if ( $lc_text =~ /$_/ ) {
            my $tag = substr( $text, $-[0], 60 );
            if ( $tag !~ /<div/ ) {
                error_register( $error_code, substr( $tag, 0, 40 ) );
            }

            # <div> tags with background are mostly ok
            elsif ( $tag !~ /background/ ) {
                error_register( $error_code, substr( $tag, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 86
###########################################################################

sub error_086_link_with_double_brackets {
    my $error_code = 86;

    if ( $lc_text =~ /(\[\[\s*https?:\/\/[^\]:]*)/ ) {
        error_register( $error_code, substr( $1, 0, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 87
###########################################################################

sub error_087_html_named_entities_without_semicolon {
    my $error_code = 87;
    my $pos        = -1;
    my $test_text  = $text;

    # IMAGE'S CAN HAVE HTML NAMED ENTITES AS PART OF THEIR FILENAME
    foreach (@Images_all) {
        $test_text =~ s/\Q$_\E//sg;
    }

    $test_text = lc($test_text);

    # REFS USE '&' FOR INPUT
    $test_text =~ s/<ref(.*?)>https?:(.*?)<\/ref>//sg;
    $test_text =~ s/https?:(.*?)\n//g;

    foreach my $entity (@HTML_NAMED_ENTITIES) {
        if ( $test_text =~ /&($entity)[^;] /g ) {
            $pos = $-[0];
        }
    }

    if ( $pos > -1 ) {
        error_register( $error_code, substr( $test_text, $pos, 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 88
###########################################################################

sub error_088_defaultsort_with_first_blank {
    my $error_code = 88;

    if (    $project ne 'arwiki'
        and $project ne 'hewiki'
        and $project ne 'plwiki'
        and $project ne 'jawiki'
        and $project ne 'yiwiki'
        and $project ne 'zhwiki' )
    {

        # Is DEFAULTSORT found in article?
        my $isDefaultsort     = -1;
        my $current_magicword = q{};
        foreach my $word (@Magicword_defaultsort) {
            if ( $isDefaultsort == -1 and index( $text, $word ) > -1 ) {
                $isDefaultsort = index( $text, $word );
                $current_magicword = $word;
            }
        }

        if ( $isDefaultsort > -1 ) {
            my $pos2 = index( substr( $text, $isDefaultsort ), '}}' );
            my $test_text = substr( $text, $isDefaultsort, $pos2 );

            my $sortkey = $test_text;
            $sortkey =~ s/^([ ]+)?$current_magicword//;
            $sortkey =~ s/^([ ]+)?://;

            if ( index( $sortkey, q{ } ) == 0 ) {
                error_register( $error_code, $test_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 89
###########################################################################

sub error_089_defaultsort_with_no_space_after_comma {
    my $error_code    = 89;
    my $isDefaultsort = -1;

    # Is DEFAULTSORT found in article?
    foreach my $word (@Magicword_defaultsort) {
        if ( $isDefaultsort == -1 and index( $text, $word ) > -1 ) {
            $isDefaultsort = index( $text, $word );
        }
    }

    if ( $isDefaultsort > -1 ) {
        my $pos2 = index( substr( $text, $isDefaultsort ), '}}' );
        my $test_text = substr( $text, $isDefaultsort, $pos2 );

        if ( $test_text =~
            /DEFAULTSORT:[\p{Cased_Letter}'-.]+,\p{Cased_Letter}/ )
        {
            error_register( $error_code, $test_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 90
###########################################################################

sub error_090_Internal_link_written_as_external_link {
    my $error_code = 90;

    # CHECK FOR en.m.wikipedia or en.wikipedida
    if ( $lc_text =~
        /($Language\.m\.wikipedia.org\/(w|wiki)|$ServerName\/(w|wiki))/o )
    {

        # Use split to include only the url.
        ( my $ack ) = split( /\s/, substr( $text, $-[0], 40 ), 2 );
        error_register( $error_code, $ack );
    }

    return ();
}

###########################################################################
## ERROR 91
###########################################################################

sub error_091_Interwiki_link_written_as_external_link {
    my $error_code = 91;
    my $test_text  = $text;

    # Remove current $projects as that is for #90
    $test_text =~ s/$ServerName//go;

    # Remove current mobile $projects as that is for 90
    $test_text =~ s/$Language\.m//go;

    if ( $test_text =~ /([[:lower:]]{2,3}(\.m)?\.wikipedia\.org\/wiki)/ ) {

        # Use split to include only the url.
        ( my $string ) =
          split( /\s/, substr( $test_text, $-[0], 40 ), 2 );

        # Links to images on other wikis are ok.  plwiki has alot.
        if ( $string !~ /\.wikipedia\.org\/wiki\/(?:Image|File):/i ) {
            error_register( $error_code, $string );
        }
    }

    return ();
}

###########################################################################
## ERROR 92
###########################################################################

sub error_092_headline_double {
    my $error_code          = 92;
    my $found_text          = q{};
    my $number_of_headlines = @Headlines;

    foreach my $i ( 0 .. $number_of_headlines - 2 ) {
        if ( $Headlines[$i] eq $Headlines[ $i + 1 ] ) {
            $found_text = $Headlines[$i];
        }
    }
    if ( $found_text ne q{} ) {
        error_register( $error_code, $found_text );
    }

    return ();
}

###########################################################################
## ERROR 93
###########################################################################

sub error_093_double_http {
    my $error_code = 93;

    if ( $lc_text =~ /(https?:[\/]{0,2}https?:)/ ) {
        error_register( $error_code, substr( $text, $-[0], 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 94
###########################################################################

sub error_094_ref_no_correct_match {
    my $error_code = 94;

    my $ref_begin = () = $lc_text =~ /<ref\b[^<>]*(?<!\/)>/g;
    my $ref_end   = () = $lc_text =~ /<\/ref>/g;

    if ( $ref_begin != $ref_end ) {
        if ( $ref_begin > $ref_end ) {
            my $snippet = get_broken_tag( '<ref', '</ref>' );
            error_register( $error_code, $snippet );
        }
        else {
            my $snippet = get_broken_tag_closing( '<ref', '</ref>' );
            error_register( $error_code, $snippet );
        }
    }
    elsif ( $lc_text =~ /(<ref name\s*=?\s*<)/ ) {
        my $test_line = substr( $text, $-[0], 40 );
        error_register( $error_code, $test_line );
    }

    return ();
}

###########################################################################
## ERROR 95
###########################################################################

sub error_095_user_signature {
    my $error_code = 95;

    if ( $lc_text =~ /$REGEX_095/o ) {
        error_register( $error_code, substr( $text, $-[0], 40 ) );
    }

    return ();
}

###########################################################################
## ERROR 96
###########################################################################

sub error_096_toc_after_1st_headline {
    my $error_code = 96;

    if ( $lc_text =~ /$Template_regex[96]__toc__/i ) {
        if (@Headlines) {
            my $toc_pos = $-[0];
            my $headline_pos = index( $text, $Headlines[0] );

            if ( $toc_pos > $headline_pos ) {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
            }
        }
        else {
            #TOC with no headlines in article
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 97
###########################################################################

sub error_097_toc_has_material_after {
    my $error_code = 97;

    if ( $lc_text =~ /$Template_regex[97]__toc__/i ) {
        my $toc_pos = $-[0];
        my $headline_pos = index( $text, $Headlines[0] );
        if ( ( $headline_pos - $toc_pos ) > 40 and $-[0] > -1 ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 98
###########################################################################

sub error_098_sub_no_correct_end {
    my $error_code = 98;

    my $sub_begin = () = $lc_text =~ /<sub/g;
    my $sub_end   = () = $lc_text =~ /<\/sub>/g;

    if ( $sub_begin != $sub_end ) {
        if ( $sub_begin > $sub_end ) {
            my $snippet = get_broken_tag( '<sub', '</sub>' );
            error_register( $error_code, $snippet );
        }
        else {
            my $snippet = get_broken_tag_closing( '<sub', '</sub>' );
            error_register( $error_code, $snippet );
        }
    }

    return ();
}

###########################################################################
## ERROR 99
###########################################################################

sub error_099_sup_no_correct_end {
    my $error_code = 99;

    my $sup_begin = () = $lc_text =~ /<sup[> ]/g;
    my $sup_end   = () = $lc_text =~ /<\/sup>/g;

    if ( $sup_begin != $sup_end ) {
        if ( $sup_begin > $sup_end ) {
            my $snippet = get_broken_tag( '<sup', '</sup>' );
            error_register( $error_code, $snippet );
        }
        else {
            my $snippet = get_broken_tag_closing( '<sup', '</sup>' );
            error_register( $error_code, $snippet );
        }
    }

    return ();
}

###########################################################################
## ERROR 100
###########################################################################

sub error_100_li_tag_no_correct_end {
    my $error_code = 100;

    if ( $lc_text =~ /<ol|<ul/ ) {
        my $list_begin = 0;
        my $list_end   = 0;

        $list_begin = () = $lc_text =~ /<ol/g;
        $list_end   = () = $lc_text =~ /<\/ol>/g;

        if ( $list_begin > $list_end ) {
            my $snippet = get_broken_tag( '<ol', '</ol>' );
            error_register( $error_code, $snippet );
        }
        elsif ( $list_begin < $list_end ) {
            error_register( $error_code, 'stray </ol>' );
        }

        $list_begin = 0;
        $list_end   = 0;

        $list_begin = () = $lc_text =~ /<ul/g;
        $list_end   = () = $lc_text =~ /<\/ul>/g;

        if ( $list_begin > $list_end ) {
            my $snippet = get_broken_tag( '<ul', '</ul>' );
            error_register( $error_code, $snippet );
        }
        elsif ( $list_begin < $list_end ) {
            error_register( $error_code, 'stray </ul>' );
        }
    }

    return ();
}

###########################################################################
## ERROR 101
###########################################################################

sub error_101_ordinal_numbers_in_sup {
    my $error_code = 101;

    if ( $lc_text =~ /\d<sup>/ ) {

        # REMOVE {{not a typo}} TEMPLATE
        $lc_text =~ s/\{\{not a typo\|[[:alpha:]\d<>\/]*\}\}//g;
        if ( $lc_text =~ /\d<sup>\s*(st|rd|th|nd)\s*<\/sup>/ ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 102
###########################################################################

sub error_102_pmid_wrong_syntax {
    my $error_code = 102;

    # CHECK FOR SPACE BEFORE PMID AS URLS CAN CONTAIN PMID
    if ( $lc_text =~ / pmid\s*([-:#])\s*/g ) {
        error_register( $error_code, substr( $text, $-[0], 40 ) );
    }

    # [http:// ... PMID 123456 ... ]
    elsif ( $lc_text =~ /\[https?:\/\/[^\]]*pmid \d[^\]]*\]/ ) {
        error_register( $error_code, substr( $text, $-[0], 40 ) );
    }

    return ();

}

###########################################################################
## ERROR 103
###########################################################################

sub error_103_pipe_in_wikilink {
    my $error_code = 103;

    if ( $lc_text =~ /\[\[([^[\]]*)\{\{!\}\}([^[\]]*)\]\]/g ) {
        error_register( $error_code, substr( $text, $-[0], 40 ) );
    }

    return ();

}

###########################################################################
## ERROR 104
###########################################################################

sub error_104_quote_marks_in_refs {
    my $error_code = 104;

    while ( $lc_text =~ /(<ref\s+name=\s*(.*?)\s*\/?>)/g ) {
        my $location = pos($lc_text) - length($1);

        my $name = $2;

        if ( $name !~ /['"].*['"]/ ) {
            if ( $name =~ /[#'"\/=>?\\\s]/ and $name !~ / group=/ ) {
                error_register( $error_code, substr( $text, $location, 40 ) );
                last;
            }
        }
    }

    return ();

}

###########################################################################
## ERROR 105
###########################################################################

sub error_105_headline_start_begin {
    my $error_code = 105;

    foreach my $line (@Lines) {

        # Check if ref is part of the heading.
        # Refs can go over multiple lines.
        if ( $line =~ /==\s*$/ ) {
            if ( $line !~ /^==/ ) {
                if ( $line !~ /<\/ref>\s*=*$/ ) {
                    my $end = rindex ( $line, '==' ) + 2;
                    my $start = $end - 40;
                    $start = 0 if ($start < 0 );
                    error_register( $error_code, substr( $line, $start, $end - $start ) );
                    last;
                }
            }
            else {
                my ($temp) = $line =~ /^([=]+)/;
                my $front = length($temp);
                ($temp) = $line =~ /([=]+)\s*$/;
                my $end = length($temp);
                if ( $front < $end ) {
                    error_register( $error_code, substr( $line, 0, 40 ) );
                    last;
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 106
###########################################################################

sub error_106_issn_wrong_syntax {
    my $error_code   = 106;
    my $error_string = q{};

    if ( $text =~ / ISSN\s*[-:#;]\s*\d/ ) {
        $error_string = substr( $text, $-[0] + 1, 16 );
    }

    # [[ISSN]] 1234-5678
    elsif ( $text =~ / \[\[ISSN\]\]\s*([-:#;]|\d)\s*\d/ ) {
        $error_string = substr( $text, $-[0] + 1, 19 );
    }

    # ISSN12345678 Check for 3 digits in case issn10= shows up in infobox
    elsif ( $text =~ / ISSN\d{3}/ ) {
        $error_string = substr( $text, $-[0] + 1, 19 );
    }

    # ISSN 12345678
    elsif ( $text =~ / ISSN\s+\d{8}\D / ) {
        $error_string = substr( $text, $-[0] + 1, 14 );
    }

    # ISSN 1234 5678
    elsif ( $text =~ / ISSN\s+\d{4}\s+\d{3}[\dX]/ ) {
        $error_string = substr( $text, $-[0] + 1, 15 );
    }

    # [http:// ... ISBN 0123456789 ... ]
    elsif ( $text =~ /\[https?:\/\/[^\]]*(ISSN \d[^\]]*\])/ ) {
        $error_string = substr( $text, $-[1], 40 );
    }

    # chop off anything not part of ISSN
    if ( $error_string ne q{} ) {
        my $x = substr( $error_string, -1, 1 );
        while ( $x !~ /[\dXx]/ ) {
            chop $error_string;
            $x = substr( $error_string, -1, 1 );
        }
        error_register( $error_code, $error_string );
    }

    return ();
}

###########################################################################
## ERROR 107
###########################################################################

sub error_107_issn_wrong_length {
    my ($found_text) = @_;
    my $error_code = 107;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( $found_text ne q{} ) {
            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 108
###########################################################################

sub error_108_issn_wrong_checksum {
    my ($found_text) = @_;
    my $error_code = 108;

    if ( $ErrorPriority[$error_code] > 0 ) {
        if ( $found_text ne q{} ) {

            error_register( $error_code, $found_text );
        }
    }

    return ();
}

###########################################################################
## ERROR 109
###########################################################################

sub error_109_include_tag_error {
    my $error_code = 109;

    my $include_begin = () = $lc_text =~ /<noinclude>/g;
    my $include_end   = () = $lc_text =~ /<\/noinclude>/g;

    if ( $include_begin != $include_end ) {
        if ( $include_begin > $include_end ) {
            my $snippet = get_broken_tag( '<noinclude>', '</noinclude>' );
            error_register( $error_code, $snippet );
        }
        else {
            my $snippet =
              get_broken_tag_closing( '<noinclude', '</noinclude>' );
            error_register( $error_code, $snippet );
        }
    }

    $include_begin = () = $lc_text =~ /<includeonly>/g;
    $include_end   = () = $lc_text =~ /<\/includeonly>/g;

    if ( $include_begin != $include_end ) {
        if ( $include_begin > $include_end ) {
            my $snippet = get_broken_tag( '<includeonly>', '</includeonly>' );
            error_register( $error_code, $snippet );
        }
        else {
            my $snippet =
              get_broken_tag_closing( '<includeonly', '</includeonly>' );
            error_register( $error_code, $snippet );
        }
    }

    $include_begin = () = $lc_text =~ /<onlyinclude>/g;
    $include_end   = () = $lc_text =~ /<\/onlyinclude>/g;

    if ( $include_begin != $include_end ) {
        if ( $include_begin > $include_end ) {
            my $snippet = get_broken_tag( '<onlyinclude>', '</onlyinclude>' );
            error_register( $error_code, $snippet );
        }
        else {
            my $snippet =
              get_broken_tag_closing( '<onlyinclude', '</onlyinclude>' );
            error_register( $error_code, $snippet );
        }
    }

    return ();
}

###########################################################################
## ERROR 110
###########################################################################

sub error_110_found_include_tag {
    my $error_code = 110;

    if ( $lc_text =~ /<noinclude|<includeonly|<onlyinclude/ ) {
        error_register( $error_code, q{} );
    }

    return ();
}

###########################################################################
## ERROR 111
###########################################################################

sub error_111_ref_after_ref_list {
    my $error_code = 111;

    my $lastref = rindex( $lc_text, '<ref>' );
    if ( $lastref > -1 ) {

        my $references = rindex( $lc_text, '<references' );

        if ( $references < $lastref and $references > 0 ) {
            error_register( $error_code, substr( $text, $lastref, 40 ) );
        }
        elsif ( $Template_list[$error_code][0] ne '-9999' ) {
            my @temp        = @{ $Template_list[3] };
            my $reftemplate = -1;

            foreach my $template (@temp) {
                my $string = '{{' . $template;
                my $temp = rindex( $lc_text, $string );
                if ( $temp > $reftemplate ) {
                    $reftemplate = $temp;
                }
            }
            if ( $reftemplate < $lastref and $reftemplate > 0 ) {
                if ( $references < $reftemplate ) {
                    error_register( $error_code,
                        substr( $text, $lastref, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 112
###########################################################################

sub error_112_css_attribute {
    my $error_code = 112;

    foreach my $regex (@REGEX_112) {
        if ( $lc_text =~ /$regex/ ) {
            error_register( $error_code, substr( $text, $-[0], 40 ) );
            last;
        }
    }

    return ();
}

######################################################################
######################################################################
######################################################################

sub error_register {
    my ( $error_code, $notice ) = @_;

    my $sth = $dbh->prepare(
        'SELECT OK FROM cw_whitelist WHERE error=? AND title=? AND project=?');
    $sth->execute( $error_code, $title, $project );

    my $whitelist = $sth->fetchrow_arrayref();

    if ( !defined($whitelist) ) {

        if ( $Dump_or_Live eq 'article' ) {
            my $ack = lc($text_original);
            my $position = index( $ack, lc($notice) );
            $notice =~ s/\n//g;
            printf( "+ %-5s%-7s%-s\n", $error_code, $position, $notice );
        }
        else {
            $notice =~ s/\n//g;

            print "\t" . $error_code . "\t" . $title . "\t" . $notice . "\n";

            $Error_number_counter[$error_code] =
              $Error_number_counter[$error_code] + 1;
            $Error_counter = $Error_counter + 1;

            insert_into_db( $error_code, $notice );
        }
    }
    else {
        print $title . ' is in whitelist with error: ' . $error_code . "\n";
    }

    return ();
}

######################################################################}

sub insert_into_db {
    my ( $code, $notice ) = @_;
    my ( $sth, $date_found, $article_title );

    $notice = substr( $notice, 0, 100 );    # Truncate notice.
    $article_title = $title;

    # Problem: sql-command insert, apostrophe ' or backslash \ in text
    #$article_title =~ s/\\/\\\\/g;
    #$article_title =~ s/'/\\'/g;
    #$notice =~ s/\\/\\\\/g;
    #$notice =~ s/'/\\'/g;

    $notice =~ s/\&/&amp;/g;
    $notice =~ s/</&lt;/g;
    $notice =~ s/>/&gt;/g;
    $notice =~ s/\"/&quot;/g;

    if ( $Dump_or_Live eq 'live' or $Dump_or_Live eq 'delay' ) {
        $date_found = strftime( '%F %T', gmtime() );
        $sth = $dbh->prepare(
            'INSERT IGNORE INTO cw_error VALUES (?, ?, ?, ?, 0, ?)');
    }
    else {
        $date_found = $time_found;
        $sth        = $dbh->prepare(
            'INSERT IGNORE INTO cw_dumpscan VALUES (?, ?, ?, ?, 0, ?)');
    }

    $sth->execute( $project, $article_title, $code, $notice, $time_found );

    return ();
}

######################################################################

# Left trim string merciless, but only to full words (result will
# never be longer than $Length characters).
sub text_reduce_to_end {
    my ( $s, $Length ) = @_;

    if ( length($s) > $Length ) {

        # Find first space in the last $Length characters of $s.
        my $pos = index( $s, q{ }, length($s) - $Length );

        # If there is no space, just take the last $Length characters.
        $pos = length($s) - $Length if ( $pos == -1 );

        return substr( $s, $pos + 1 );
    }
    else {
        return $s;
    }
}

######################################################################

sub two_column_display {

    # Print all output in two column well formed
    if ( $Dump_or_Live ne 'list' ) {
        my $text1 = shift;
        my $text2 = shift;
        printf "%-30s %-30s\n", $text1, $text2;
    }

    return ();
}

######################################################################

sub usage {
    print {*STDERR} "To scan a dump:\n"
      . "$0 -p dewiki --dumpfile DUMPFILE\n"
      . "$0 -p nds_nlwiki --dumpfile DUMPFILE\n"
      . "$0 -p nds_nlwiki --dumpfile DUMPFILE --silent\n"
      . "To scan a list of pages live:\n"
      . "$0 -p dewiki\n"
      . "$0 -p dewiki --silent\n"
      . "$0 -p dewiki --load new/done/dump/last_change/old\n";

    return ();
}

###########################################################################
###########################################################################
## MAIN PROGRAM
###########################################################################
###########################################################################

my ( $load_mode, $dump_date_for_output, $config_name );

GetOptions(
    'load=s'      => \$load_mode,
    'project|p=s' => \$project,
    'database'    => \$DbName,
    'host'        => \$DbServer,
    'password=s'  => \$DbPassword,
    'user'        => \$DbUsername,
    'dumpfile=s'  => \$DumpFilename,
    'listfile=s'  => \$ListFilename,
    'article=s'   => \$ArticleName,
    'tt'          => \$Template_Tiger,
    'check'       => \$CheckOnlyOne,
    'config|c=s'  => \$config_name
);

if ( defined $config_name ) {
    open( my $file, '<:encoding(UTF-8)', $config_name )
      or die 'Could not open file ' . $config_name . "\n";
    while ( my $line = <$file> ) {
        chomp($line);
        my @words = ( split / /, $line );
        $DbName     = $words[1] if ( $words[0] =~ /--database/ );
        $DbUsername = $words[1] if ( $words[0] =~ /--user/ );
        $DbPassword = $words[1] if ( $words[0] =~ /--password/ );
        $DbServer   = $words[1] if ( $words[0] =~ /--host/ );
    }
    close($file)
      or die 'Could not close file ' . $config_name . "\n";
}
else {
    die("No config file entered, for example: -c checkwiki.cfg\n");
}

if ( !defined($project) ) {
    usage();
    die("$0: No project name, for example: \"-p dewiki\"\n");
}

if ( $load_mode eq 'dump' ) {
    $Dump_or_Live = 'dump';
    require MediaWiki::DumpFile::Pages;

    # GET DATE FROM THE DUMP FILENAME
    $dump_date_for_output = $DumpFilename;
    $dump_date_for_output =~
s/^(?:.*\/)?\Q$project\E-(\d{4})(\d{2})(\d{2})-pages-articles\.xml(.*?)$/$1-$2-$3/;
}
elsif ( $load_mode eq 'live' )    { $Dump_or_Live = 'live'; }
elsif ( $load_mode eq 'delay' )   { $Dump_or_Live = 'delay'; }
elsif ( $load_mode eq 'list' )    { $Dump_or_Live = 'list'; }
elsif ( $load_mode eq 'article' ) { $Dump_or_Live = 'article'; }
else { die("No load name, for example: \"-l live\"\n"); }

# OPEN TEMPLATETIGER FILE
if ( $Template_Tiger == 1 ) {
    if ( !$dump_date_for_output ) {
        $dump_date_for_output = 'list';
    }
    require File::Temp;
    $TTFile = File::Temp->new(
        DIR      => $TTDIRECTORY,
        TEMPLATE => $project . q{-} . $dump_date_for_output . '-XXXX',
        SUFFIX   => '.txt',
        UNLINK   => 0
    );
    $TTFilename =
      $TTDIRECTORY . q{/} . $project . q{-} . $dump_date_for_output . '.txt';
    binmode( $TTFile, ':encoding(UTF-8)' );
}

if ( $Dump_or_Live ne 'article' ) {
    print q{-} x 80, "\n" if ( $Dump_or_Live ne 'list' );

    two_column_display( 'Start time:',
        ( strftime '%a %b %e %H:%M:%S %Y', localtime ) );
    $time_found = strftime( '%F %T', gmtime() );
    two_column_display( 'Project:',   $project );
    two_column_display( 'Scan type:', $Dump_or_Live . ' scan' );
}

open_db();
clearDumpscanTable() if ( $Dump_or_Live eq 'dump' );
getErrors();
readMetadata();
readTemplates();

print q{-} x 80, "\n" if ( $Dump_or_Live ne 'list' );

# MAIN ROUTINE - SCAN PAGES FOR ERRORS
scan_pages();

updateDumpDate($dump_date_for_output) if ( $Dump_or_Live eq 'dump' );
update_table_cw_error_from_dump()     if ( $Dump_or_Live ne 'article' );
delete_done_article_from_db()         if ( $Dump_or_Live ne 'article' );

# CLOSE TEMPLATETIGER FILE
if ( defined($TTFile) ) {

    # Move Templatetiger file to spool.
    $TTFile->close() or die( $! . "\n" );
    if ( !rename( $TTFile->filename(), $TTFilename ) ) {
        die(    'Could not rename temporary Templatetiger file from'
              . $TTFile->filename() . ' to '
              . $TTFilename
              . "\n" );
    }
    if ( !chmod( 0664, $TTFilename ) ) {
        die( 'Could not chmod 664 Templatetiger file ' . $TTFilename . "\n" );
    }
    undef($TTFile);
}

close_db();

if ( $Dump_or_Live ne 'article' ) {
    print q{-} x 80, "\n" if ( $Dump_or_Live ne 'list' );
    two_column_display( 'Articles checked:', $artcount );
    two_column_display( 'Errors found:',     ++$Error_counter );

    $time_end = time() - $time_start;
    $time_end = sprintf '%d hours, %d minutes and %d seconds',
      ( gmtime $time_end )[ 2, 1, 0 ];
    two_column_display( 'Program run time:', $time_end );
    two_column_display( 'PROGRAM FINISHED',  q{} );
    print q{-} x 80, "\n" if ( $Dump_or_Live ne 'list' );
}
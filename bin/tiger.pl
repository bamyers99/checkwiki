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
##       VERSION: 2015/12/10
##
###########################################################################

use strict;
use warnings;
use utf8;

use lib '/data/project/checkwiki/perl/lib/perl5';
use Business::ISBN qw( valid_isbn_checksum );
use DBI;
use File::Temp;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use LWP::UserAgent;
use POSIX qw(strftime);
use URI::Escape;
use feature 'unicode_strings';

use MediaWiki::DumpFile::Pages;
use MediaWiki::API;
use MediaWiki::Bot;

# Different versions of Perl at home vs labs.  Use labs version
#use v5.14.2;

# When using the most current version available
use v5.18.2;
no if $] >= 5.018, warnings => "experimental::smartmatch";

binmode( STDOUT, ":encoding(UTF-8)" );

##############################
##  Program wide variables
##############################

our $Dump_or_Live = q{};    # Scan modus (dump, live, delay)

our $CheckOnlyOne = 0;      # Check only one error or all errors

our $ServerName  = q{};     # Address where api can be found
our $project     = q{};     # Name of the project 'dewiki'
our $end_of_dump = q{};     # When last article from dump reached
our $artcount    = 0;       # Number of articles processed
our $file_size   = 0;       # How many MB of the dump has been processed.

# Database configuration
our $DbName;
our $DbServer;
our $DbUsername;
our $DbPassword;

our $dbh;

# MediaWiki::DumpFile variables
our $pages = q{};

# Time program starts
our $time_start = time();    # Start timer in secound
our $time_end   = time();    # End time in secound
our $time_found = time();    # For column "Found" in cw_error

# Template list retrieved from Translation file
our @Template_list;

# Article name for article mode
our $ArticleName;

# Filename that contains a list of articles titles for list mode
our $ListFilename;

# Filename that contains the dump file for dump mode
our $DumpFilename;

# Should Template Tiger output be generated?
our $Template_Tiger = 0;
our $TTFile;
our $TTFilename;
our $TTDIRECTORY = '/data/project/templatetiger/public_html/dumps/';
our $TTnumber    = 0;

# Total number of Errors
our $Number_of_error_description = 0;

##############################
##  Wiki-special variables
##############################

our @Namespace;    # Namespace values
                   # 0 number
                   # 1 namespace in project language
                   # 2 namespace in english language

our @Namespace_aliases;    # Namespacealiases values
                           # 0 number
                           # 1 namespacealias

our @Namespace_cat;        # All namespaces for categorys
our @Namespace_image;      # All namespaces for images
our @Namespace_templates;  # All namespaces for templates
our @Template_regex;       # Template regex fron translation file
our $Image_regex = q{};    # Regex used in get_images()
our $Cat_regex   = q{};    # Regex used in get_categories()
our $User_regex  = q{};    # Regex used in error_095_user_signature();
our $Draft_regex = q{};    # Regex used in error_095_user_signature();

our $Magicword_defaultsort;

our $Error_counter = -1;    # Number of found errors in all article
our @ErrorPriorityValue;    # Priority value each error has

our @Error_number_counter = (0) x 150;    # Error counter for individual errors

our @INTER_LIST = qw( af  als an  ar  az  bg  bs  bn
  ca  cs  cy  da  de  el  en  eo  es  et  eu  fa  fi
  fr  fy  gv  he  hi  hr  hu  hy  id  is  it  ja
  jv  ka  kk  ko  la  lb  lt  ms  nds nl  nn  no  pl
  pt  ro  ru  sh  sk  sl  sr  sv  sw  ta  th  tr  uk
  ur  uz  vi  zh  simple  nds_nl );

our @FOUNDATION_PROJECTS = qw( b  c  d  n  m  q  s  v  w
  meta  mw  nost  wikt  wmf  voy
  commons     foundation   incubator   phabricator
  quality     species      testwiki    wikibooks
  wikidata    wikimedia    wikinews    wikiquote
  wikisource  wikispecies  wiktionary  wikiversity
  wikivoyage );

# See http://turner.faculty.swau.edu/webstuff/htmlsymbols.html
our @HTML_NAMED_ENTITIES = qw( aacute Aacute acirc Acirc aelig AElig
  agrave Agrave alpha Alpha aring Aring asymp atilde Atilde auml Auml beta Beta
  brvbar bull ccedil Ccedil cent chi Chi clubs copy crarr darr dArr deg
  delta Delta diams divide eacute Eacute ecirc Ecirc egrave Egrave
  epsilon Epsilon equiv eta Eta eth ETH euml Euml euro fnof frac12 frac14
  frac34 frasl gamma Gamma ge harr hArr hearts hellip iacute Iacute icirc Icirc
  iexcl igrave Igrave infin int iota Iota iquest iuml Iuml kappa Kappa
  lambda Lambda laquo larr lArr ldquo le loz lsaquo lsquo micro middot
  mu Mu ne not ntilde Ntilde nu Nu oacute Oacute ocirc Ocirc oelig OElig
  ograve Ograve oline omega Omega omicron Omicron ordf ordm oslash Oslash
  otilde Otilde ouml Ouml para part permil phi Phi pi Pi piv plusm pound prod
  psi Psi quot radic raquo rarr rArr rdquo reg rho Rho raquo rsaquo rsquo
  scaron Scaron sect sigma Sigma sigmaf spades sum sup1 sup2 sup3 szlig
  tau Tau theta Theta thetasym thorn THORN tilde trade uacute Uacute uarr uArr
  ucirc Ucirc ugrave Ugrave upsih upsilon Upsilon uuml Uuml xi Xi yacute Yacute
  yen yuml Yuml zeta Zeta );

# FOR #011. DO NOT CONVERT GREEK LETTERS THAT LOOK LIKE LATIN LETTERS.
# Alpha (A), Beta (B), Epsilon (E), Zeta (Z), Eta (E), Kappa (K), kappa (k), Mu (M), Nu (N), nu (v), Omicron (O), omicron (o), Rho (P), Tau (T), Upsilon (Y), upsilon (o) and Chi (X).
our @HTML_NAMED_ENTITIES_011 = qw( aacute Aacute acirc Acirc aelig AElig
  agrave Agrave alpha aring Aring asymp atilde Atilde auml Auml beta
  brvbar bull ccedil Ccedil cent chi clubs copy crarr darr dArr deg
  delta Delta diams divide eacute Eacute ecirc Ecirc egrave Egrave
  epsilon equiv eta eth ETH euml Euml euro fnof frac12 frac14
  frac34 frasl gamma Gamma ge harr hArr hearts hellip iacute Iacute icirc Icirc
  iexcl igrave Igrave infin int iota Iota iquest iuml Iuml
  lambda Lambda laquo larr lArr ldquo le loz lsaquo lsquo micro middot
  mu ne not ntilde Ntilde oacute Oacute ocirc Ocirc oelig OElig
  ograve Ograve oline omega Omega ordf ordm oslash Oslash
  otilde Otilde ouml Ouml para part permil phi Phi pi Pi piv plusm pound prod
  psi Psi quot radic raquo rarr rArr rdquo reg rho raquo rsaquo rsquo
  scaron Scaron sect sigma Sigma sigmaf spades sum sup1 sup2 sup3 szlig
  tau theta Theta thetasym thorn THORN tilde trade uacute Uacute uarr uArr
  ucirc Ucirc ugrave Ugrave upsih upsilon uuml Uuml xi Xi yacute Yacute
  yen yuml Yuml zeta Zeta );

###############################
## Variables for one article
###############################

our $title         = q{};    # Title of current article
our $text          = q{};    # Text of current article
our $lc_text       = q{};    # Text of current article in lower case
our $text_original = q{};    # Text of article with comments only removed

our $page_namespace;         # Namespace of page
our $page_is_redirect       = 'no';
our $page_is_disambiguation = 'no';

our $Category_counter = -1;

our @Category;               # 0 pos_start
                             # 1 pos_end
                             # 2 category	Test
                             # 3 linkname	Linkname
                             # 4 original	[[Category:Test|Linkname]]

our @Interwiki;              # 0 pos_start
                             # 1 pos_end
                             # 2 interwiki	Test
                             # 3 linkname	Linkname
                             # 4 original	[[de:Test|Linkname]]
                             # 5 language

our $Interwiki_counter = -1;

our @Templates_all;          # All templates
our @Template;               # Templates with values
                             # 0 number of template
                             # 1 templatename
                             # 2 template_row
                             # 3 attribut
                             # 4 value

our $Number_of_template_parts = -1;    # Number of all template parts

our @Links_all;                        # All links
our @Images_all;                       # All images
our @Ref;                              # All ref
our @Headlines;                        # All headlines
our @Lines;                            # Text seperated in lines

###########################################################################
###########################################################################
###########################################################################
## OPEN DATABASE
###########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : '' ),
        $DbUsername,
        $DbPassword,
        {
            RaiseError           => 1,
            AutoCommit           => 1,
            mysql_enable_utf8mb4    => 1,
            mysql_auto_reconnect => 1,
        }
    ) or die( "Could not connect to database: " . DBI::errstr() . "\n" );

	$dbh->do('SET NAMES utf8mb4')
	   or die($dbh->errstr);

    #$dbh->do("SET SESSION wait_timeout=36000");

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

    my $sql_text =
        "UPDATE cw_overview SET Last_Dump = '"
      . $date
      . "' WHERE Project = '"
      . $project . "';";

    my $sth = $dbh->prepare($sql_text);
    $sth->execute;

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
        $pretty = sprintf( "%7.2f", $bytes ) . ' MB';
    }

    if ( ( $bytes = $bytes / 1024 ) > 1 ) {
        $pretty = sprintf( "%0.3f", $bytes ) . ' GB';
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
            $my_title = $1 . ':' . ucfirst($2);
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
        my $sth =
          $dbh->prepare(
            'DELETE FROM cw_error WHERE Title = ? AND Project = ?;');
        $sth->execute( $title, $project );
    }

    return ();
}

###########################################################################
## GET @ErrorPriorityValue
###########################################################################

sub getErrors {
    my $error_count = 0;

    my $sth =
      $dbh->prepare(
        'SELECT COUNT(*) FROM cw_overview_errors WHERE project = ?;');
    $sth->execute($project);

    $Number_of_error_description = $sth->fetchrow();

    #$Number_of_error_description = 97;

    $sth =
      $dbh->prepare('SELECT prio FROM cw_overview_errors WHERE project = ?;');
    $sth->execute($project);

    foreach my $i ( 1 .. $Number_of_error_description ) {
        $ErrorPriorityValue[$i] = $sth->fetchrow();
        if ( $ErrorPriorityValue[$i] > 0 ) {
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

    $ServerName = $project;
    if (
        !(
               $ServerName =~ s/^nds_nlwiki$/nds-nl.wikipedia.org/
            || $ServerName =~ s/^commonswiki$/commons.wikimedia.org/
            || $ServerName =~ s/^([a-z]+)wiki$/$1.wikipedia.org/
            || $ServerName =~ s/^([a-z]+)wikisource$/$1.wikisource.org/
            || $ServerName =~ s/^([a-z]+)wikiversity$/$1.wikiversity.org/
            || $ServerName =~ s/^([a-z]+)wiktionary$/$1.wiktionary.org/
            || $ServerName =~ s/^([a-z]+)wikivoyage$/$1.wikivoyage.org/
        )
      )
    {
        die( "Couldn't calculate server name for project" . $project . "\n" );
    }

    my $url = 'http://' . $ServerName . '/w/api.php';

    # Setup MediaWiki::API
    my $mw = MediaWiki::API->new();
    $mw->{config}->{api_url} = $url;

    # See https://www.mediawiki.org/wiki/API:Siteinfo
    my $res = $mw->api(
        {
            action => 'query',
            meta   => 'siteinfo',
            siprop =>
              'general|namespaces|namespacealiases|statistics|magicwords',
        }
    ) || die $mw->{error}->{code} . ': ' . $mw->{error}->{details} . "\n";

    if ( $Dump_or_Live eq 'dump' ) {
        print_line();
        two_column_display( 'Load metadata from:', $url );
        two_column_display( 'Sitename:', $res->{query}->{general}->{sitename} );
        two_column_display( 'Base:',     $res->{query}->{general}->{base} );
        two_column_display( 'Pages online:',
            $res->{query}->{statistics}->{pages} );
        two_column_display( 'Images online:',
            $res->{query}->{statistics}->{images} );
    }

    foreach my $id ( keys %{ $res->{query}->{namespaces} } ) {
        my $name      = $res->{query}->{namespaces}->{$id}->{'*'};
        my $canonical = $res->{query}->{namespaces}->{$id}->{'canonical'};
        push( @Namespace, [ $id, $name, $canonical ] );

        # Store special namespaces in convenient variables.
        if ( $id == 2 or $id == 3 ) {
            $User_regex = $User_regex . '\[\[' . $name . ':|';
        }
        elsif ( $id == 118 or $id == 119 ) {
            $Draft_regex = $Draft_regex . '\[\[' . $name . ':|';
        }
        elsif ( $id == 6 ) {
            @Namespace_image = ( $name, $canonical );
            $Image_regex = $name;
        }
        elsif ( $id == 10 ) {
            @Namespace_templates = ($name);
            push( @Namespace_templates, $canonical ) if ( $name ne $canonical );
        }
        elsif ( $id == 14 ) {
            @Namespace_cat = ($name);
            $Cat_regex     = $name;
            if ( $name ne $canonical ) {
                push( @Namespace_cat, $canonical );
                $Cat_regex = $name . "|" . $canonical;
            }
        }
    }

    foreach my $entry ( @{ $res->{query}->{namespacealiases} } ) {
        my $name = $entry->{'*'};
        if ( $entry->{id} == 2 or $entry->{id} == 3 ) {
            $User_regex = $User_regex . '\[\[' . $name . ':|';
        }
        elsif ( $entry->{id} == 6 ) {
            push( @Namespace_image, $name );
            $Image_regex = $Image_regex . "|" . $name;
        }
        elsif ( $entry->{id} == 10 ) {
            push( @Namespace_templates, $name );
        }
        elsif ( $entry->{id} == 14 ) {
            push( @Namespace_cat, $name );
            $Cat_regex = $Cat_regex . "|" . $name;
        }

        # Store all aliases.
        push( @Namespace_aliases, [ $entry->{id}, $name ] );
    }

    foreach my $id ( @{ $res->{query}->{magicwords} } ) {
        my $aliases = $id->{aliases};
        my $name    = $id->{name};
        $Magicword_defaultsort = $aliases if ( $name eq 'defaultsort' );
    }

    chop($User_regex);     # Drop off final '|'
    chop($Draft_regex);    # Drop off final '|'

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
                    $Template_regex[$i] = '\{\{' . lc($template_sql) . '|';
                }
                else {
                    $Template_regex[$i] =
                      $Template_regex[$i] . '\{\{' . lc($template_sql) . '|';
                }
                push( @{ $Template_list[$i] }, lc($template_sql) );
            }
        }
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

    given ($Dump_or_Live) {

        when ('dump') {

            $pages = MediaWiki::DumpFile::Pages->new($DumpFilename);

            # CHECK FILE_SIZE IF ONLY UNCOMPRESSED
            if ( $DumpFilename !~ /(.*?)\.xml\.bz2$/ ) {
                $file_size = ( stat($DumpFilename) )[7];
            }

            while ( defined( $page = $pages->next ) && $end_of_dump eq 'no' ) {
                next if ( $page->namespace != 0 );    #NS=0 IS ARTICLE NAMESPACE
                set_variables_for_article();
                $title = $page->title;
                if ( $title ne "" ) {
                    update_ui() if ++$artcount % 500 == 0;
                    $page_namespace = 0;
                    $title          = case_fixer($title);
                    $revision       = $page->revision;
                    $text           = $revision->text;

                    check_article();

                    #$end_of_dump = 'yes' if ( $artcount > 10000 );
                    #$end_of_dump = 'yes' if ( $Error_counter > 40000 )
                }
            }
        }

        when ('live')    { live_scan(); }
        when ('delay')   { delay_scan(); }
        when ('list')    { list_scan(); }
        when ('article') { article_scan(); }
        default          { die("Wrong Load_mode entered \n"); }
    }
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
            protocol => 'http',
            host     => $ServerName,
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
            protocol => 'http',
            host     => $ServerName,
        }
    );

    if ( !defined($ListFilename) ) {
        die "The filename of the list was not defined\n";
    }

    open( my $list_of_titles, '<:encoding(UTF-8)', $ListFilename )
      or die 'Could not open file ' . $ListFilename . "\n";

    while ( my $line = <$list_of_titles> ) {
        set_variables_for_article();
        chomp($line);
        $title = $line;
        $text  = $bot->get_text($title);
        if ( defined($text) ) {
            check_article();
        }
    }

    close($list_of_titles);
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
            protocol => 'http',
            host     => $ServerName,
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
            protocol => 'http',
            host     => $ServerName,
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
        if ( $title ne "" ) {
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

    # REMOVES FROM $text ANY CONTENT BETWEEN <source> </sources TAGS.
    # CALLS #014
    get_source();

    # REMOVES FROM $text ANY CONTENT BETWEEN <code> </code> TAGS.
    # CALLS #15
    get_code();

    # REMOVE FROM $text ANY CONTENT BETWEEN <syntaxhighlight> TAGS.
    get_syntaxhighlight();

    # REMOVES FROM $text ANY CONTENT BETWEEN <math> </math> TAGS.
    # Goes after code and syntaxhighlight so it doesn't catch <math.h>
    # CALLS #013
    get_math();

    # REMOVE FROM $text ANY CONTENT BETWEEN <hiero> TAGS.
    get_hiero();

    # REMOVE FROM $text ANY CONTENT BETWEEN <score> TAGS.
    get_score();

    # REMOVE FROM $text ANY CONTENT BETWEEN <score> TAGS.
    get_graph();

    $lc_text = lc($text);

    #------------------------------------------------------
    # Following interacts with other get_* or error #'s
    #------------------------------------------------------

    # CREATES @Ref - USED IN #81
    #get_ref();

    # CREATES @Templates_all - USED IN #12, #31
    # CALLS #43
    get_templates_all();

    # DOES TEMPLATETIGER
    # USES @Templates_all
    # CREATES @template - USED IN #59, #60
    get_template();

    # CREATES @Links_all & @Images_all-USED IN #65, #66, #67, #68, #74, #76, #82
    # CALLS #10
    #get_links();

    # SETS $page_is_redirect
    #check_for_redirect();

    # CREATES @Category - USED IN #17, #18, #21, #22, #37, #53, #91
    #get_categories();

    # CREATES @Interwiki - USED IN #45, #51, #53
    #get_interwikis();

    # CREATES @Lines
    # USED IN #02, #09, #26, #32, #34, #38, #39, #40-#42, #54,  #75
    #create_line_array();

    # CREATES @Headlines
    # USES @Lines
    # USED IN #07, #08, #25, #44, #51, #52, #57, #58, #62, #83, #84, #92
    #get_headlines();

    # EXCEPT FOR get_* THAT REMOVES TAGS FROM $text, FOLLOWING DON'T NEED
    # TO BE PROCESSED BY ANY get_* ROUTINES: 3-6, 11, 13-16, 19, 20, 23, 24,
    # 27, 35, 36, 43, 46-50, 54-56, 59-61, 63-74, 76-80, 82, 84-90
    #error_check();

    return ();
}

###########################################################################
## FIND MISSING COMMENTS TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_comments {

    if ( $text =~ /<!--/ ) {
        #my $comments_begin = 0;
        #my $comments_end   = 0;

        #$comments_begin = () = $text =~ /<!--/g;
        #$comments_end   = () = $text =~ /-->/g;

        #if ( $comments_begin > $comments_end ) {
        #    my $snippet = get_broken_tag( '<!--', '-->' );
        #    error_005_Comment_no_correct_end($snippet);
        #}

        $text =~ s/<!--(.*?)-->//sg;
    }

    return ();
}

###########################################################################
## FIND MISSING NOWIKI TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_nowiki {
    my $test_text = lc($text);

    if ( $test_text =~ /<nowiki>/ ) {
        #my $nowiki_begin = 0;
        #my $nowiki_end   = 0;

        #$nowiki_begin = () = $test_text =~ /<nowiki>/g;
        #$nowiki_end   = () = $test_text =~ /<\/nowiki>/g;

        #if ( $nowiki_begin > $nowiki_end ) {
        #    my $snippet = get_broken_tag( '<nowiki>', '</nowiki>' );
        #    error_023_nowiki_no_correct_end($snippet);
        #}

        $text =~ s/<nowiki>(.*?)<\/nowiki>//sg;
    }

    return ();
}

###########################################################################
## FIND MISSING PRE TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_pre {
    my $test_text = lc($text);

    if ( $test_text =~ /<pre>/ ) {
        #my $pre_begin = 0;
        #my $pre_end   = 0;

        #$pre_begin = () = $test_text =~ /<pre>/g;
        #$pre_end   = () = $test_text =~ /<\/pre>/g;

        #if ( $pre_begin > $pre_end ) {
        #    my $snippet = get_broken_tag( '<pre>', '</pre>' );
        #    error_024_pre_no_correct_end($snippet);
        #}

        $text =~ s/<pre>(.*?)<\/pre>//sg;
    }

    return ();
}

###########################################################################
## FIND MISSING MATH TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_math {
    my $test_text = lc($text);

    if ( $test_text =~ /<math>|<math / ) {
        #my $math_begin = 0;
        #my $math_end   = 0;

        #$math_begin = () = $test_text =~ /<math/g;
        #$math_end   = () = $test_text =~ /<\/math>/g;

        #if ( $math_begin > $math_end ) {
        #    my $snippet = get_broken_tag( '<math', '</math>' );
        #    error_013_Math_no_correct_end($snippet);
        #}

        # LEAVE MATH TAG IN.  CAUSES PROBLEMS WITH #61, #65 and #67
        $text =~ s/<math(.*?)<\/math>/<math><\/math>/sg;
    }

    return ();
}

###########################################################################
## FIND MISSING SOURCE TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_source {
    my $test_text = lc($text);

    if ( $test_text =~ /<source/ ) {
        #my $source_begin = 0;
        #my $source_end   = 0;

        #$source_begin = () = $test_text =~ /<source/g;
        #$source_end   = () = $test_text =~ /<\/source>/g;

        #if ( $source_begin > $source_end ) {
        #    my $snippet = get_broken_tag( '<source', '</source>' );
        #    error_014_Source_no_correct_end($snippet);
        #}

        #$text =~ s/<source(.*?)<\/source>//sg;
    }

    return ();
}

###########################################################################
## FIND MISSING CODE TAGS AND REMOVE EVERYTHING BETWEEN THE TAGS
###########################################################################

sub get_code {
    my $test_text = lc($text);

    if ( $test_text =~ /<code>/ ) {
        #my $code_begin = 0;
        #my $code_end   = 0;

        #$code_begin = () = $test_text =~ /<code>/g;
        #$code_end   = () = $test_text =~ /<\/code>/g;

        #if ( $code_begin > $code_end ) {
        #    my $snippet = get_broken_tag( '<code>', '</code>' );
        #    error_015_Code_no_correct_end($snippet);
        #}

        $text =~ s/<code>(.*?)<\/code>//sg;
    }

    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE SYNTAXHIGHLIGHT TAGS
###########################################################################

sub get_syntaxhighlight {

    $text =~ s/<syntaxhighlight(.*?)<\/syntaxhighlight>//sg;

    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE HIERO TAGS
###########################################################################

sub get_hiero {

    $text =~ s/<hiero>(.*?)<\/hiero>/<hiero><\/hiero>/sg;

    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE SCORE TAGS
###########################################################################

sub get_score {

    $text =~ s/<score(.*?)<\/score>//sg;

    return ();
}

###########################################################################
## REMOVE EVERYTHING BETWEEN THE GRAPH TAGS
###########################################################################

sub get_graph {

    $text =~ s/<graph(.*?)<\/graph>//sg;

    return ();
}

###########################################################################
## GET TABLES
###########################################################################

sub get_tables {

    my $test_text = $text;

    my $tag_open_num  = () = $test_text =~ /\{\|/g;
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
        my $test_text = uc($text);
        if ( $test_text =~ / ISBN\s*([-]|[:]|[#]|[;]|10|13)\s*/g ) {
            my $output = substr( $test_text, pos($test_text) - 11, 40 );

            # INFOBOX CAN HAVE "| ISBN10 = ".
            # ALSO DON'T CHECK ISBN (10|13)XXXXXXXXXX
            if (    ( $output !~ /\|\s*ISBN(10|13)\s*=/g )
                and ( $output !~ /ISBN\s*([-]|[:]|[#]|[;]){0,1}\s*(10|13)\d/g )
              )
            {
                error_069_isbn_wrong_syntax($output);
            }
        }
        elsif ( $test_text =~ / \[\[ISBN\]\]\s*([:]|[-]|[#]|[;])+\s*\d/g ) {
            my $output = substr( $text, $-[0], 40 );
            error_069_isbn_wrong_syntax($output);
        }

        # CHECK FOR CASES OF ISBNXXXXXXXXX.  INFOBOXES CAN HAVE ISBN10
        # SO NEED TO WORK AROUND THAT.
        elsif ( $test_text =~ / ISBN\d[-\d ][-\d]/g ) {
            my $output = substr( $text, $-[0], 40 );
            error_069_isbn_wrong_syntax($output);
        }
        elsif ( $test_text =~ / (10|13)-ISBN/g ) {
            my $output = substr( $text, $-[0], 40 );
            error_069_isbn_wrong_syntax($output);
        }

        while ( $test_text =~ /ISBN([ ]|[-]|[=]|[:])/g ) {
            my $pos_start = pos($test_text) - 5;
            my $current_isbn = substr( $test_text, $pos_start );

            $current_isbn =~
/\b(?:ISBN(?:-?1[03])?:?\s*|(ISBN\s*=\s*))([\dX ‐—–-]{4,24}[\dX])\b/gi;

            if ( defined $2 ) {
                my $isbn       = $2;
                my $isbn_strip = $2;
                $isbn_strip =~ s/[^0-9X]//g;

                my $digits = length($isbn_strip);

                if (    index( $isbn_strip, 'X' ) != 9
                    and index( $isbn_strip, 'X' ) > -1 )
                {
                    error_071_isbn_wrong_pos_X($isbn);
                }
                elsif ( $digits == 10 ) {
                    if ( valid_isbn_checksum($isbn_strip) != 1 ) {
                        error_072_isbn_10_wrong_checksum($isbn);
                    }
                }
                elsif ( $digits == 13 ) {
                    if ( $isbn_strip =~ /X/g ) {
                        error_073_isbn_13_wrong_checksum($isbn_strip);
                    }
                    else {
                        if ( valid_isbn_checksum($isbn_strip) != 1 ) {
                            error_073_isbn_13_wrong_checksum($isbn);
                        }
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

    # Delete all breaks --> only one line
    # Delete all tabs --> better for output
    $test_text =~ s/\n|\t//g;

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
        else {
            error_043_template_no_correct_end( substr( $temp_text, 0, 40 ) );
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
    foreach (@Templates_all) {
        my $current_template = $_;
        $current_template =~ s/^\{\{//;
        $current_template =~ s/\}\}$//;
        $current_template =~ s/^ //g;

        foreach (@Namespace_templates) {
            $current_template =~ s/^$_://i;
        }

        $number_of_templates++;
        my $template_name = q{};

        my @template_split = split( /\|/, $current_template );

        if ( index( $current_template, '|' ) == -1 ) {

            # If no pipe; for example {{test}}
            $template_name = $current_template;
            next;
        }

        if ( index( $current_template, '|' ) > -1 ) {

            # Templates with pipe {{test|attribute=value}}

            # Get template name
            $template_split[0] =~ s/^ //g;
            $template_name = $template_split[0];

            if ( index( $template_name, '_' ) > -1 ) {
                $template_name =~ s/_/ /g;
            }
            if ( index( $template_name, '  ' ) > -1 ) {
                $template_name =~ s/  / /g;
            }

            shift(@template_split);

            # Get next part of template
            my $template_part = q{};
            my @template_part_array;
            undef(@template_part_array);

            foreach (@template_split) {
                $template_part = $template_part . $_;

                # Check for []
                my $beginn_brackets = ( $template_part =~ tr/[[/[[/ );
                my $end_brackets    = ( $template_part =~ tr/]]/]]/ );

                # Check for {}
                my $beginn_curly_brackets = ( $template_part =~ tr/{{/{{/ );
                my $end_curly_brackets    = ( $template_part =~ tr/}}/}}/ );

                # Template part complete ?
                if (    $beginn_brackets eq $end_brackets
                    and $beginn_curly_brackets eq $end_curly_brackets )
                {

                    push( @template_part_array, $template_part );
                    $template_part = q{};
                }
                else {
                    $template_part = $template_part . '|';
                }

            }

            # OUTPUT If only templates {{{xy|value}}
            my $template_part_number           = -1;
            my $template_part_without_attribut = -1;

            foreach (@template_part_array) {
                $template_part = $_;

                $template_part_number++;
                $template_part_counter++;

                $template_name =~ s/^[ ]+|[ ]+$//g;

                $Template[$template_part_counter][0] = $number_of_templates;
                $Template[$template_part_counter][1] = $template_name;
                $Template[$template_part_counter][2] = $template_part_number;

                my $attribut = q{};
                my $value    = q{};
                if ( index( $template_part, '=' ) > -1 ) {

                    #template part with "="   {{test|attribut=value}}

                    my $pos_equal     = index( $template_part, '=' );
                    my $pos_lower     = index( $template_part, '<' );
                    my $pos_next_temp = index( $template_part, '{{' );
                    my $pos_table     = index( $template_part, '{|' );
                    my $pos_bracket   = index( $template_part, '[' );

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
                        $attribut =
                          substr( $template_part, 0,
                            index( $template_part, '=' ) );
                        $value =
                          substr( $template_part,
                            index( $template_part, '=' ) + 1 );
                    }
                    else {
                     # Problem:  {{test|value<ref name="sdfsdf"> sdfhsdf</ref>}}
                     # Problem   {{test|value{{test2|name=teste}}|sdfsdf}}
                        $template_part_without_attribut =
                          $template_part_without_attribut + 1;
                        $attribut = $template_part_without_attribut;
                        $value    = $template_part;
                    }
                }
                else {
                    # Template part with no "="   {{test|value}}
                    $template_part_without_attribut =
                      $template_part_without_attribut + 1;
                    $attribut = $template_part_without_attribut;
                    $value    = $template_part;
                }

                $attribut =~ s/^[ ]+|[ ]+$//g;
                $value =~ s/^[ ]+|[ ]+$//g;

                $Template[$template_part_counter][3] = $attribut;
                $Template[$template_part_counter][4] = $value;

                $Number_of_template_parts++;

                # Output for TemplateTiger
                if ( $Template_Tiger == 1 ) {
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
    my $link_text_2 = q{};
    my $brackets_begin;
    my $brackets_end;

    $test_text =~ s/\n//g;

    while ( $test_text =~ /\[\[/g ) {

        my $link_text = substr( $test_text, pos($test_text) - 2 );
        while ( $link_text =~ /\]\]/g ) {

            $link_text_2 =
              q{ } . substr( $link_text, 0, pos($link_text) ) . q{ };
            $brackets_begin = ( $link_text_2 =~ tr/[[/[[/ );
            $brackets_end   = ( $link_text_2 =~ tr/]]/]]/ );

            last if ( $brackets_begin == $brackets_end );
        }

        if ( $brackets_begin == $brackets_end ) {

            $link_text_2 = substr( $link_text_2, 1, length($link_text_2) - 2 );
            push( @Links_all, $link_text_2 );

            if ( $link_text_2 =~ /^\[\[\s*(?:$Image_regex):/i ) {
                push( @Images_all, $link_text_2 );
            }

        }
        else {
            error_010_count_square_breaks( substr( $link_text, 0, 40 ) );

        }
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

    foreach (@Namespace_cat) {

        my $namespace_cat_word = $_;
        my $pos_end            = 0;
        my $pos_start          = 0;
        my $counter            = 0;
        my $test_text          = $text;
        my $search_word        = $namespace_cat_word;

        while ( $test_text =~ /\[\[([ ]+)?($search_word:)/ig ) {
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

                $Category[$counter][2] =~ s/\[\[//g;        # Delete [[
                $Category[$counter][2] =~ s/^([ ]+)?//g;    # Delete blank
                $Category[$counter][2] =~ s/\]\]//g;        # Delete ]]
                $Category[$counter][2] =~ s/^$namespace_cat_word//i;
                $Category[$counter][2] =~ s/^://;           # Delete :
                $Category[$counter][2] =~ s/\|(.)*//g;      # Delete |xy
                $Category[$counter][2] =~ s/^ //g;          # Delete blank
                $Category[$counter][2] =~ s/ $//g;          # Delete blank

                # Filter linkname
                $Category[$counter][3] = q{}
                  if ( index( $Category[$counter][3], '|' ) == -1 );
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

    if ( $text =~ /\[\[([a-z][a-z]|als|nds|nds_nl|simple):/i ) {

        foreach (@INTER_LIST) {

            my $current_lang = $_;
            my $pos_start    = 0;
            my $pos_end      = 0;
            my $counter      = 0;
            my $test_text    = $text;
            my $search_word  = $current_lang;

            while ( $test_text =~ /\[\[$search_word:/ig ) {
                $pos_start = pos($test_text) - length($search_word) - 1;
                $pos_end   = index( $test_text, ']]', $pos_start );
                $pos_start = $pos_start - 2;

                if ( $pos_start > -1 and $pos_end > -1 ) {

                    $counter                = ++$Interwiki_counter;
                    $pos_end                = $pos_end + 2;
                    $Interwiki[$counter][0] = $pos_start;
                    $Interwiki[$counter][1] = $pos_end;
                    $Interwiki[$counter][4] =
                      substr( $test_text, $pos_start, $pos_end - $pos_start );
                    $Interwiki[$counter][5] = $current_lang;
                    $Interwiki[$counter][2] = $Interwiki[$counter][4];
                    $Interwiki[$counter][3] = $Interwiki[$counter][4];

                    $Interwiki[$counter][2] =~ s/\]\]//g;       # Delete ]]
                    $Interwiki[$counter][2] =~ s/\|(.)*//g;     # Delete |xy
                    $Interwiki[$counter][2] =~ s/^(.)*://gi;    # Delete [[xx:
                    $Interwiki[$counter][2] =~ s/^ //g;         # Delete blank
                    $Interwiki[$counter][2] =~ s/ $//g;         # Delete blank;

                    if ( index( $Interwiki[$counter][3], '|' ) == -1 ) {
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
    foreach (@Lines) {

        if ( substr( $_, 0, 1 ) eq '=' ) {
            print 'HEADLINE:' . $title . "\n"
              if ( $first == 0 and $title eq $_ );
            $first = 2;
            push( @Headlines, $_ );
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
        error_098_sub_no_correct_end();
    }
    else {
        get_tables();    # CALLS #28
        get_isbn();      # CALLS #69, #70, #71, #72 ISBN CHECKS

        error_001_template_with_word_template();
        error_002_have_br();
        error_003_have_ref();
        error_004_html_text_style_elements_a();

        #error_005_Comment_no_correct_end('');             # get_comments()
        error_006_defaultsort_with_special_letters();
        error_007_headline_only_three();
        error_008_headline_start_end();
        error_009_more_then_one_category_in_a_line();

        #error_010_count_square_breaks('');                # get_links()
        error_011_html_named_entities();
        error_012_html_list_elements();

        #error_013_Math_no_correct_end('');                # get_math
        #error_014_Source_no_correct_end('');              # get_source()
        #error_015_Code_no_correct_end('');                # get_code()
        error_016_unicode_control_characters();
        error_017_category_double();
        error_018_category_first_letter_small();
        error_019_headline_only_one();
        error_020_symbol_for_dead();
        error_021_category_is_english();
        error_022_category_with_space();

        #error_023_nowiki_no_correct_end('');              # get_nowiki()
        #error_024_pre_no_correct_end('');                 # get_pre()
        error_025_headline_hierarchy();
        error_026_html_text_style_elements();
        error_027_unicode_syntax();

        #error_028_table_no_correct_end('');               # get_tables()
        error_029_gallery_no_correct_end();

        #error_030                                         # DEACTIVATED
        error_031_html_table_elements();
        error_032_double_pipe_in_link();
        error_033_html_text_style_elements_underline();
        error_034_template_programming_elements();

        #error_035                                         # DEACTIVATED
        error_036_redirect_not_correct();
        error_037_title_with_special_letters_and_no_defaultsort();
        error_038_html_text_style_elements_italic();
        error_039_html_text_style_elements_paragraph();
        error_040_html_text_style_elements_font();
        error_041_html_text_style_elements_big();
        error_042_html_text_style_elements_strike();

        #error_043_template_no_correct_end('');            # get_templates()
        error_044_headline_with_bold();
        error_045_interwiki_double();
        error_046_count_square_breaks_begin();
        error_047_template_no_correct_begin();
        error_048_title_in_text();
        error_049_headline_with_html();
        error_050_dash();
        error_051_interwiki_before_last_headline();
        error_052_category_before_last_headline();
        error_053_interwiki_before_category();
        error_054_break_in_list();
        error_055_html_text_style_elements_small_double();
        error_056_arrow_as_ASCII_art();
        error_057_headline_end_with_colon();
        error_058_headline_with_capitalization();
        error_059_template_value_end_with_br();
        error_060_template_parameter_with_problem();
        error_061_reference_with_punctuation();
        error_062_url_without_http();
        error_063_html_text_style_elements_small_ref_sub_sup();
        error_064_link_equal_linktext();
        error_065_image_description_with_break();
        error_066_image_description_with_full_small();
        error_067_reference_after_punctuation();
        error_068_link_to_other_language();

        #error_069_isbn_wrong_syntax('');                  # get_isbn()
        #error_070_isbn_wrong_length('');                  # get_isbn()
        #error_071_isbn_wrong_pos_X('');                   # get_isbn()
        #error_072_isbn_10_wrong_checksum('');             # get_isbn()
        #error_073_isbn_13_wrong_checksum('');             # get_isbn()
        error_074_link_with_no_target();
        error_075_indented_list();
        error_076_link_with_no_space();
        error_077_image_description_with_partial_small();
        error_078_reference_double();

        #error_079                                         # DEACTIVATED
        error_080_external_link_with_line_break();
        error_081_ref_double();
        error_082_link_to_other_wikiproject();
        error_083_headline_only_three_and_later_level_two();
        error_084_section_without_text();
        error_085_tag_without_content();
        error_086_link_with_two_brackets_to_external_source();
        error_087_html_named_entities_without_semicolon();
        error_088_defaultsort_with_first_blank();
        error_089_defaultsort_with_no_space_after_comma();
        error_090_Internal_link_written_as_an_external_link();
        error_091_Interwiki_link_written_as_an_external_link();
        error_092_headline_double();
        error_093_double_http();
        error_094_ref_no_correct_match();
        error_095_user_signature();
        error_096_toc_after_first_headline();
        error_097_toc_has_material_after_it();
        error_098_sub_no_correct_end();
        error_099_sup_no_correct_end();
        error_100_list_tag_no_correct_end();
        error_101_ordinal_numbers_in_sup();
        error_102_pmid_wrong_syntax();
        error_103_pipe_magicword_in_wikilink();
        error_104_quote_marks_in_refs();
        error_105_headline_start_begin();
    }

    return ();
}

###########################################################################
##  ERROR 01
###########################################################################

sub error_001_template_with_word_template {
    my $error_code = 1;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Namespace_templates) {
                my $template = lc($_);
                if ( $lc_text =~ /(\{\{\s*$template:)/ ) {
                    error_register( $error_code, substr( $text, $-[0], 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 02
###########################################################################

sub error_002_have_br {
    my $error_code = 2;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $lc_text =~
/(<\s*br\/[^ ]>|<\s*br[^ ]\/>|<\s*br[^ \/]>|<[^ w]br\s*>|<\s*br\s*\/[^ ]>|<\s*br\s*clear|<small\s*\/\s*>|<\s*center\s*\/\s*>)/i
              )
            {
                my $test_line = substr( $text, $-[0], 40 );
                $test_line =~ s/[\n\r]//mg;
                error_register( $error_code, $test_line );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 03
###########################################################################

sub error_003_have_ref {
    my $error_code = 3;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if (   index( $text, '<ref>' ) > -1
                or index( $text, '<ref name' ) > -1 )
            {

                my $test      = "false";
                my $test_text = $lc_text;

                $test = "true"
                  if (  $test_text =~ /<[ ]?+references>/
                    and $test_text =~ /<[ ]?+\/references>/ );
                $test = "true" if ( $test_text =~ /<[ ]?+references[ ]?+\/>/ );
                $test = "true" if ( $test_text =~ /<[ ]?+references group/ );
                $test = "true" if ( $test_text =~ /\{\{[ ]?+refbegin/ );
                $test = "true" if ( $test_text =~ /\{\{[ ]?+refend/ );
                $test = "true" if ( $test_text =~ /\{\{[ ]?+reflist/ );

                if ( $Template_list[$error_code][0] ne '-9999' ) {

                    my @ack = @{ $Template_list[$error_code] };

                    for my $temp (@ack) {
                        if ( $test_text =~ /\{\{[ ]?+($temp)/ ) {
                            $test = "true";
                        }
                    }
                }
                if ( $test eq "false" ) {
                    error_register( $error_code, q{} );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 04
###########################################################################

sub error_004_html_text_style_elements_a {
    my $error_code = 4;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = index( $lc_text, '<a ' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 05
###########################################################################

sub error_005_Comment_no_correct_end {
    my ($comment) = @_;
    my $error_code = 5;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne q{}
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, substr( $comment, 0, 40 ) );
        }
    }

    return ();
}

###########################################################################
## ERROR 06
###########################################################################

sub error_006_defaultsort_with_special_letters {
    my $error_code = 6;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            # Is DEFAULTSORT found in article?
            my $isDefaultsort = -1;
            foreach ( @{$Magicword_defaultsort} ) {
                $isDefaultsort = index( $text, $_ ) if ( $isDefaultsort == -1 );
            }

            if ( $isDefaultsort > -1 ) {
                my $pos2 = index( substr( $text, $isDefaultsort ), '}}' );
                my $test_text = substr( $text, $isDefaultsort, $pos2 );

                my $test_text2 = $test_text;

                # Remove ok letters
                $test_text =~ s/[-–:,\.\/\(\)0-9 A-Za-z!\?']//g;

                # Too many to figure out what is right or not
                $test_text =~ s/#//g;
                $test_text =~ s/\+//g;

                given ($project) {
                    when ('cswiki') {
                        $test_text =~ s/[čďěňřšťžČĎŇŘŠŤŽ]//g;
                    }
                    when ('dawiki') { $test_text =~ s/[ÆØÅæøå]//g; }
                    when ('dawiki') {
                        $test_text =~ s/[ĈĜĤĴŜŬĉĝĥĵŝŭ]//g;
                    }
                    when ('eowiki') {
                        $test_text =~ s/[ĈĜĤĴŜŬĉĝĥĵŝŭ]//g;
                    }
                    when ('hewiki') {
                        $test_text =~
s/[אבגדהוזחטיכךלמםנןסעפףצץקרשת]//g
                    }
                    when ('fiwiki') { $test_text =~ s/[ÅÄÖåäö]//g; }
                    when ('nowiki') { $test_text =~ s/[ÆØÅæøå]//g; }
                    when ('nnwiki') { $test_text =~ s/[ÆØÅæøå]//g; }
                    when ('rowiki') { $test_text =~ s/[ăîâşţ]//g; }
                    when ('ruwiki') {
                        $test_text =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюя]//g;
                    }
                    when ('svwiki') { $test_text =~ s/[ÅÄÖåäö]//g; }
                    when ('ukwiki') {
                        $test_text =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюяiїґ]//g;
                    }
                }

                if ( $test_text ne q{} ) {
                    $test_text2 = "{{" . $test_text2 . "}}";
                    error_register( $error_code, $test_text2 );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 07
###########################################################################

sub error_007_headline_only_three {
    my $error_code = 7;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if ( $Headlines[0]
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            if ( $Headlines[0] =~ /===/ ) {

                my $found_level_two = 'no';
                foreach (@Headlines) {
                    if ( $_ =~ /^==[^=]/ ) {
                        $found_level_two = 'yes';    #found level two (error 83)
                    }
                }
                if ( $found_level_two eq 'no' ) {
                    error_register( $error_code, $Headlines[0] );
                }
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        foreach (@Headlines) {
            my $current_line  = $_;
            my $current_line1 = $current_line;
            my $current_line2 = $current_line;

            $current_line2 =~ s/\t//gi;
            $current_line2 =~ s/[ ]+/ /gi;
            $current_line2 =~ s/ $//gi;

            if (    $current_line1 =~ /^==/
                and not( $current_line2 =~ /==$/ )
                and index( $current_line, '<ref' ) == -1
                and ( $page_namespace == 0 or $page_namespace == 104 ) )
            {
                error_register( $error_code, substr( $current_line, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 09
###########################################################################

sub error_009_more_then_one_category_in_a_line {
    my $error_code = 9;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $text =~
                /\[\[($Cat_regex):(.*?)\]\]([ ]*)\[\[($Cat_regex):(.*?)\]\]/g )
            {

                my $error_text =
                    '[['
                  . $1 . ':'
                  . $2 . ']]'
                  . $3 . '[['
                  . $4 . ':'
                  . $5 . "]]\n";
                error_register( $error_code, substr( $error_text, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 10
###########################################################################

sub error_010_count_square_breaks {
    my ($comment) = @_;
    my $error_code = 10;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne q{}
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $pos = -1;

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
        }
    }

    return ();
}

###########################################################################
## ERROR 12
###########################################################################

sub error_012_html_list_elements {
    my $error_code = 12;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $lc_text;

            if (   index( $test_text, '<ol>' ) > -1
                or index( $test_text, '<ul>' ) > -1
                or index( $test_text, '<li>' ) > -1 )
            {

                # Only search for <ol>. <ol type an <ol start can be used.
                if (    index( $test_text, '<ol start' ) == -1
                    and index( $test_text, '<ol type' ) == -1
                    and index( $test_text, '<ol reversed' ) == -1 )
                {

                    # <ul> or <li> in templates can be only way to do a list.
                    $test_text = $text;
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if ( $comment ne q{} ) {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 16
###########################################################################

sub error_016_unicode_control_characters {
    my $error_code = 16;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            # 200B is a problem with IPA characters in some wikis (czwiki)
            # \p{Co} or PUA is Private Unicode Area

            my $search = "\x{200E}|\x{FEFF}";
            if ( $project eq 'enwiki' ) {
                $search = $search
                  . "|\x{200B}|\x{2028}|\x{202A}|\x{202C}|\x{202D}|\x{202E}|\x{00A0}|\x{00AD}";
            }

            if ( $text =~ /($search)/ or $text =~ /(\p{Co})/ ) {
                my $test_text = $text;
                my $pos = index( $test_text, $1 );
                $test_text = substr( $test_text, $pos, 40 );
                $test_text =~ s/\p{Co}/\{PUA\}/;
                $test_text =~ s/\x{200B}/\{200B\}/;
                $test_text =~ s/\x{200E}/\{200E\}/;
                $test_text =~ s/\x{202A}/\{202A\}/;
                $test_text =~ s/\x{2028}/\{2028\}/;
                $test_text =~ s/\x{202C}/\{202C\}/;
                $test_text =~ s/\x{202D}/\{202D\}/;
                $test_text =~ s/\x{202E}/\{202E\}/;
                $test_text =~ s/\x{FEFF}/\{FEFF\}/;
                $test_text =~ s/\x{00A0}/\{00A0\}/;

                error_register( $error_code, $test_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 17
###########################################################################

sub error_017_category_double {
    my $error_code = 17;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach my $i ( 0 .. $Category_counter - 1 ) {
                my $test = $Category[$i][2];

                if ( $test ne q{} ) {
                    $test = uc( substr( $test, 0, 1 ) ) . substr( $test, 1 );

                    foreach my $j ( $i + 1 .. $Category_counter ) {
                        my $test2 = $Category[$j][2];

                        if ( $test2 ne q{} ) {
                            $test2 =
                              uc( substr( $test2, 0, 1 ) )
                              . substr( $test2, 1 );
                        }

                        if ( $test eq $test2 ) {
                            error_register( $error_code, $Category[$i][2] );
                        }
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

sub error_018_category_first_letter_small {
    my $error_code = 18;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $project ne 'commonswiki' ) {

            foreach my $i ( 0 .. $Category_counter ) {
                my $test_letter = substr( $Category[$i][2], 0, 1 );
                if ( $test_letter =~ /([a-z]|ä|ö|ü)/ ) {
                    error_register( $error_code, $Category[$i][2] );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 19
###########################################################################

sub error_019_headline_only_one {
    my $error_code = 19;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Headlines) {
                if ( $_ =~ /^=[^=]/ ) {
                    error_register( $error_code, substr( $_, 0, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 20
###########################################################################

sub error_020_symbol_for_dead {
    my $error_code = 20;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = index( $text, '&dagger;' );
            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 21
###########################################################################

sub error_021_category_is_english {
    my $error_code = 21;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {
            if (    $project ne 'commonswiki'
                and $Namespace_cat[0] ne 'Category' )
            {

                foreach my $i ( 0 .. $Category_counter ) {
                    my $current_cat = lc( $Category[$i][4] );

                    if ( index( $current_cat, lc( $Namespace_cat[1] ) ) > -1 ) {
                        error_register( $error_code, $current_cat );
                    }
                }
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            foreach my $i ( 0 .. $Category_counter ) {

                if (   $Category[$i][4] =~ /[^ \|]\s+\]\]$/
                    or $Category[$i][4] =~ /\[\[ /
                    or $Category[$i][4] =~ /\[\[[^:]+(\s+:|:\s+)/ )
                {
                    error_register( $error_code, $Category[$i][4] );
                }
            }
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne q{}
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne q{}
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
            error_register( $error_code, $comment );
        }
    }

    return ();
}

###########################################################################
## ERROR 25
###########################################################################

sub error_025_headline_hierarchy {
    my $error_code = 25;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $number_headline = -1;
            my $old_headline    = q{};
            my $new_headline    = q{};

            foreach (@Headlines) {
                $number_headline = $number_headline + 1;
                $old_headline    = $new_headline;
                $new_headline    = $_;

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
                    }
                }
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = index( $lc_text, '<b>' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 27
###########################################################################

sub error_027_unicode_syntax {
    my $error_code = 27;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            my $pos = -1;
            $pos = index( $text, '&#322;' )   if ( $pos == -1 );  # l in Wrozlaw
            $pos = index( $text, '&#x0124;' ) if ( $pos == -1 );  # l in Wrozlaw
            $pos = index( $text, '&#8211;' )  if ( $pos == -1 );  # –

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 28
###########################################################################

sub error_028_table_no_correct_end {
    my ($comment) = @_;
    my $error_code = 28;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $comment ne q{}
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

            my $test = "false";

            if ( $Template_list[$error_code][0] ne '-9999' ) {

                my @ack = @{ $Template_list[$error_code] };

                for my $temp (@ack) {
                    if ( index( $lc_text, $temp ) > -1 ) {
                        $test = "true";
                    }
                }
            }
            if ( $test eq "false" ) {
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
    my $error_code = 29;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $lc_text;

            if ( $test_text =~ /<gallery/ ) {
                my $gallery_begin = 0;
                my $gallery_end   = 0;

                $gallery_begin = () = $test_text =~ /<gallery/g;
                $gallery_end   = () = $test_text =~ /<\/gallery>/g;

                if ( $gallery_begin > $gallery_end ) {
                    my $snippet = get_broken_tag( '<gallery', '</gallery>' );
                    error_register( $error_code, $snippet );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 31
###########################################################################

sub error_031_html_table_elements {
    my $error_code = 31;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

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
        }
    }

    return ();
}

###########################################################################
## ERROR 32
###########################################################################

sub error_032_double_pipe_in_link {
    my $error_code = 32;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {
            foreach (@Lines) {
                if ( $_ =~ /\[\[[^\]:\{]+\|([^\]\{]+\||\|)/g ) {
                    my $pos              = pos($_);
                    my $first_part       = substr( $_, 0, $pos );
                    my $second_part      = substr( $_, $pos );
                    my @first_part_split = split( /\[\[/, $first_part );
                    foreach (@first_part_split) {
                        $first_part = '[[' . $_;  # Find last link in first_part
                    }
                    my $current_line = $first_part . $second_part;
                    error_register( $error_code,
                        substr( $current_line, 0, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 33
###########################################################################

sub error_033_html_text_style_elements_underline {
    my $error_code = 33;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = index( $lc_text, '<u>' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 34
###########################################################################

sub error_034_template_programming_elements {
    my $error_code = 34;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $text =~
/(\{\{\{|#if:|#ifeq:|#switch:|#ifexist:|\{\{fullpagename}}|\{\{sitename}}|\{\{namespace}}|\{\{basepagename}}|\{\{pagename}}|\{\{subpagename}}|\{\{subst:)/i
              )
            {
                my $test_line = substr( $text, $-[0], 40 );
                $test_line =~ s/[\n\r]//mg;
                error_register( $error_code, $test_line );
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if ( $page_is_redirect eq 'yes' ) {
            if ( $lc_text =~ /#redirect[ ]?+[^ :\[][ ]?+\[/ ) {
                error_register( $error_code, substr( $text, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 37
###########################################################################

sub error_037_title_with_special_letters_and_no_defaultsort {
    my $error_code = 37;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and $Category_counter > -1
            and length($title) > 2 )
        {

            # Is DEFAULTSORT found in article?
            my $isDefaultsort = -1;
            foreach ( @{$Magicword_defaultsort} ) {
                $isDefaultsort = index( $text, $_ ) if ( $isDefaultsort == -1 );
            }

            if ( $isDefaultsort == -1 ) {

                my $test_title = $title;
                if ( $project ne 'enwiki' ) {
                    $test_title = substr( $test_title, 0, 5 );
                }

                # Titles such as 'Madonna (singer)' are OK
                $test_title =~ s/\(//g;
                $test_title =~ s/\)//g;

                # Remove ok letters
                $test_title =~ s/[-:,\.\/0-9 A-Za-z!\?']//g;

                # Too many to figure out what is right or not
                $test_title =~ s/#//g;
                $test_title =~ s/\+//g;

                given ($project) {
                    when ('cswiki') {
                        $test_title =~ s/[čďěňřšťžČĎŇŘŠŤŽ]//g;
                    }
                    when ('dawiki') { $test_title =~ s/[ÆØÅæøå]//g; }
                    when ('eowiki') {
                        $test_title =~ s/[ĈĜĤĴŜŬĉĝĥĵŝŭ]//g;
                    }
                    when ('hewiki') {
                        $test_title =~
s/[אבגדהוזחטיכךלמםנןסעפףצץקרשת]//g
                    }
                    when ('fiwiki') { $test_title =~ s/[ÅÄÖåäö]//g; }
                    when ('nowiki') { $test_title =~ s/[ÆØÅæøå]//g; }
                    when ('nnwiki') { $test_title =~ s/[ÆØÅæøå]//g; }
                    when ('rowiki') { $test_title =~ s/[ăîâşţ]//g; }
                    when ('ruwiki') {
                        $test_title =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюя]//g;
                    }
                    when ('svwiki') { $test_title =~ s/[ÅÄÖåäö]//g; }
                    when ('ukwiki') {
                        $test_title =~
s/[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЫЪЭЮЯабвгдежзийклмнопрстуфхцчшщьыъэюяiїґ]//g;
                    }
                }

                if ( $test_title ne q{} ) {
                    error_register( $error_code, q{} );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 38
###########################################################################

sub error_038_html_text_style_elements_italic {
    my $error_code = 38;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = index( $lc_text, '<i>' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 39
###########################################################################

sub error_039_html_text_style_elements_paragraph {
    my $error_code = 39;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $lc_text;
            if ( $test_text =~ /<p>|<p / ) {

                # <P> ARE STILL NEEDED IN <REF>
                $test_text =~ s/<ref(.*?)<\/ref>//sg;

                my $pos = index( $test_text, '<p>' );
                if ( $pos > -1 ) {
                    error_register( $error_code,
                        substr( $test_text, $pos, 40 ) );
                }
                $pos = index( $test_text, '<p ' );
                if ( $pos > -1 ) {
                    error_register( $error_code,
                        substr( $test_text, $pos, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 40
###########################################################################

sub error_040_html_text_style_elements_font {
    my $error_code = 40;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = index( $lc_text, '<font' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 41
###########################################################################

sub error_041_html_text_style_elements_big {
    my $error_code = 41;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = index( $lc_text, '<big>' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 42
###########################################################################

sub error_042_html_text_style_elements_strike {
    my $error_code = 42;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = index( $lc_text, '<strike>' );

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 43
###########################################################################

sub error_043_template_no_correct_end {
    my ($comment) = @_;
    my $error_code = 43;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (
            $comment ne q{}
            and (  $page_namespace == 0
                or $page_namespace == 6
                or $page_namespace == 104 )
          )
        {
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Headlines) {
                my $headline = $_;

                if ( index( $headline, "'''" ) > -1
                    and not $headline =~ /[^']''[^']/ )
                {

                    if ( index( $headline, "<ref" ) < 0 ) {
                        error_register( $error_code,
                            substr( $headline, 0, 40 ) );
                    }
                }
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

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
        }
    }

    return ();
}

###########################################################################
## ERROR 46
###########################################################################

sub error_046_count_square_breaks_begin {
    my $error_code = 46;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $test_text     = $text;
            my $test_text_1_a = $test_text;
            my $test_text_1_b = $test_text;

            if ( ( $test_text_1_a =~ s/\[\[//g ) !=
                ( $test_text_1_b =~ s/\]\]//g ) )
            {
                my $found_text = q{};
                my $begin_time = time();
                while ( $test_text =~ /\]\]/g ) {

                    # Begin of link
                    my $pos_end     = pos($test_text) - 2;
                    my $link_text   = substr( $test_text, 0, $pos_end );
                    my $link_text_2 = q{};
                    my $beginn_square_brackets = 0;
                    my $end_square_brackets    = 1;
                    while ( $link_text =~ /\[\[/g ) {

                        # Find currect end - number of [[==]]
                        my $pos_start = pos($link_text);
                        $link_text_2 = substr( $link_text, $pos_start );
                        $link_text_2 = ' ' . $link_text_2 . ' ';

                        # Test the number of [[and  ]]
                        my $link_text_2_a = $link_text_2;
                        $beginn_square_brackets =
                          ( $link_text_2_a =~ s/\[\[//g );
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
                        $found_text =
                          text_reduce_to_end( $found_text, 50 ) . ']]';
                    }

                    last
                      if ( $found_text ne q{} or $begin_time + 60 > time() )
                      ;    # End if a problem was found, no endless run
                }

                if ( $found_text ne q{} ) {
                    error_register( $error_code, $found_text );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 47
###########################################################################

sub error_047_template_no_correct_begin {
    my $error_code = 47;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $tag_open         = "{{";
            my $tag_close        = "}}";
            my $look_ahead_open  = 0;
            my $look_ahead_close = 0;
            my $look_ahead       = 0;
            my $test_text        = $text;

            my $tag_open_num  = () = $test_text =~ /$tag_open/g;
            my $tag_close_num = () = $test_text =~ /$tag_close/g;

            my $diff = $tag_close_num - $tag_open_num;

            if ( $diff > 0 ) {

                my $pos_open  = rindex( $test_text, $tag_open );
                my $pos_close = rindex( $test_text, $tag_close );
                my $pos_close2 =
                  rindex( $test_text, $tag_close, $pos_open - 2 );

                while ( $diff > 0 ) {
                    if ( $pos_close2 == -1 ) {
                        error_register( $error_code,
                            substr( $text, $pos_close, 40 ) );
                        $diff = -1;
                    }
                    elsif ( $pos_close2 > $pos_open and $look_ahead < 0 ) {
                        error_register( $error_code,
                            substr( $text, $pos_close, 40 ) );
                        $diff--;
                    }
                    else {
                        $pos_close = $pos_close2;
                        $pos_close2 =
                          rindex( $test_text, $tag_close, $pos_close - 2 );
                        $pos_open =
                          rindex( $test_text, $tag_open, $pos_open - 2 );
                        if ( $pos_close2 > 0 ) {
                            $look_ahead_close =
                              rindex( $test_text, $tag_close, $pos_close2 - 2 );
                            $look_ahead_open =
                              rindex( $test_text, $tag_open, $pos_open - 2 );
                            $look_ahead = $look_ahead_open - $look_ahead_close;
                        }
                    }
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $test_text = $text;

            # OK (MUST) TO HAVE IN IMAGEMAPS, INCLUDEONLY AND TIMELINE
            $test_text =~ s/<imagemap>(.*?)<\/imagemap>//sg;
            $test_text =~ s/<includeonly>(.*?)<\/includeonly>//sg;
            $test_text =~ s/<timeline>(.*?)<\/timeline>//sg;

            my $pos = index( $test_text, '[[' . $title . ']]' );

            if ( $pos == -1 ) {
                $pos = index( $test_text, '[[' . $title . '|' );
            }

            if ( $pos != -1 ) {
                $test_text = substr( $test_text, $pos, 40 );
                $test_text =~ s/\n//g;
                error_register( $error_code, $test_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 49
###########################################################################

sub error_049_headline_with_html {
    my $error_code = 49;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $test_text = $lc_text;
            my $pos       = -1;
            $pos = index( $test_text, '<h2>' )  if ( $pos == -1 );
            $pos = index( $test_text, '<h3>' )  if ( $pos == -1 );
            $pos = index( $test_text, '<h4>' )  if ( $pos == -1 );
            $pos = index( $test_text, '<h5>' )  if ( $pos == -1 );
            $pos = index( $test_text, '<h6>' )  if ( $pos == -1 );
            $pos = index( $test_text, '</h2>' ) if ( $pos == -1 );
            $pos = index( $test_text, '</h3>' ) if ( $pos == -1 );
            $pos = index( $test_text, '</h4>' ) if ( $pos == -1 );
            $pos = index( $test_text, '</h5>' ) if ( $pos == -1 );
            $pos = index( $test_text, '</h6>' ) if ( $pos == -1 );
            if ( $pos != -1 ) {
                $test_text = substr( $test_text, $pos, 40 );
                $test_text =~ s/\n//g;
                error_register( $error_code, $test_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 50
###########################################################################

sub error_050_dash {
    my $error_code = 50;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
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
    }

    return ();
}

###########################################################################
## ERROR 51
###########################################################################

sub error_051_interwiki_before_last_headline {
    my $error_code = 51;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

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
        }
    }

    return ();
}

###########################################################################
## ERROR 52
###########################################################################

sub error_052_category_before_last_headline {
    my $error_code = 52;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        my $number_of_headlines = @Headlines;
        my $pos                 = -1;

        if ( $number_of_headlines > 0 ) {

            $pos =
              index( $text, $Headlines[ $number_of_headlines - 1 ] )
              ;    #pos of last headline
        }
        if ( $pos > -1
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

            my $found_text = q{};
            for ( my $i = 0 ; $i <= $Category_counter ; $i++ ) {
                if ( $pos > $Category[$i][0] ) {
                    $found_text = $Category[$i][4];
                }
            }

            if ( $found_text ne q{} ) {
                error_register( $error_code, substr( $found_text, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 53
###########################################################################

sub error_053_interwiki_before_category {
    my $error_code = 53;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (    $Category_counter > -1
            and $Interwiki_counter > -1
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

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
    }

    return ();
}

###########################################################################
## ERROR 54
###########################################################################

sub error_054_break_in_list {
    my $error_code = 54;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Lines) {

                if ( index( $_, q{*} ) == 0 ) {
                    if ( $_ =~ /<br([ ]+)?(\/)?([ ]+)?>([ ]+)?$/i ) {
                        error_register( $error_code, substr( $_, 0, 40 ) );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 55
###########################################################################

sub error_055_html_text_style_elements_small_double {
    my $error_code = 55;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $lc_text;
            if ( index( $test_text, '<small>' ) > -1 ) {

                if ( $test_text =~
                    /\<small\>\s*\<small\>|\<\/small\>\s*\<\/small\>/g )
                {
                    error_register( $error_code, substr( $text, $-[0], 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 56
###########################################################################

sub error_056_arrow_as_ASCII_art {
    my $error_code = 56;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos = -1;
            $pos = index( $lc_text, '->' );
            $pos = index( $lc_text, '<-' ) if $pos == -1;
            $pos = index( $lc_text, '<=' ) if $pos == -1;
            $pos = index( $lc_text, '=>' ) if $pos == -1;

            if ( $pos > -1 ) {
                my $test_text = substr( $text, $pos - 10, 40 );
                $test_text =~ s/\n//g;
                error_register( $error_code, $test_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 57
###########################################################################

sub error_057_headline_end_with_colon {
    my $error_code = 57;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Headlines) {
                if ( $_ =~ /:[ ]?[ ]?[ ]?[=]+([ ]+)?$/ ) {
                    error_register( $error_code, substr( $_, 0, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 58
###########################################################################

sub error_058_headline_with_capitalization {
    my $error_code = 58;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Headlines) {
                my $current_line_normal = $_;

                $current_line_normal =~ s/[^\p{Uppercase}\p{Lowercase},&]//g
                  ;    # Only english characters and comma

                my $current_line_uc = uc($current_line_normal);
                if ( length($current_line_normal) > 10 ) {

                    if ( $current_line_normal eq $current_line_uc ) {

                        # Found ALL CAPS HEADLINE(S)
                        my $check_ok = 'yes';

                        # Check comma
                        if ( index( $current_line_normal, q{,} ) > -1 ) {
                            my @comma_split =
                              split( ',', $current_line_normal );
                            foreach (@comma_split) {
                                if ( length($_) < 10 ) {
                                    $check_ok = 'no';
                                }
                            }
                        }
                        if ( $check_ok eq 'yes' and $_ ne q{} ) {
                            error_register( $error_code, substr( $_, 0, 40 ) );
                        }
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 59
###########################################################################

sub error_059_template_value_end_with_br {
    my $error_code = 59;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text = q{};
            foreach my $i ( 0 .. $Number_of_template_parts ) {

                if (
                    $Template[$i][4] =~ /<br([ ]+)?(\/)?([ ]+)?>([ ])?([ ])?$/ )
                {
                    if (    $found_text eq q{}
                        and $Template[$i][1] !~ /marriage/i
                        and $Template[$i][1] !~ /nihongo/i )
                    {
                        $found_text =
                          $Template[$i][3] . '=...'
                          . text_reduce_to_end( $Template[$i][4], 20 );
                    }
                }
            }
            if ( $found_text ne q{} ) {
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 60
###########################################################################

sub error_060_template_parameter_with_problem {
    my $error_code = 60;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach my $i ( 0 .. $Number_of_template_parts ) {

                if ( $Template[$i][3] =~ /\[|\]|\|:|\*/ ) {
                    my $found_text = $Template[$i][1] . ', ' . $Template[$i][3];
                    error_register( $error_code, $found_text );
                    last;
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 61
###########################################################################

sub error_061_reference_with_punctuation {
    my $error_code = 61;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            # Not sure about elipse (...).  "{1,2}[^\.]" to not check for them
            # Space after !, otherwise will catch false-poistive from tables
            if ( $text =~ /<\/ref>[ ]{0,2}(\.{1,2}[^\.]|,|\?|:|;|! )/i ) {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
            }
            elsif ( $text =~
                /(<ref name[^\/]*\/>[ ]{0,2}(\.{1,2}[^\.]|,|\?|:|;|! ))/i )
            {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
            }
            elsif ( $Template_list[$error_code][0] ne '-9999' ) {

                my $pos = -1;
                my @ack = @{ $Template_list[$error_code] };

                for my $temp (@ack) {
                    if ( $text =~
                        /\{\{[ ]?+$temp[^\}]*\}{2,4}[ ]{0,2}([\.,\?:;]|! )/
                        and $pos == -1 )
                    {
                        $pos = $-[0];
                    }
                }
                if ( $pos > -1 ) {
                    error_register( $error_code, substr( $text, $pos, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 62
###########################################################################

sub error_062_url_without_http {
    my $error_code = 62;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $lc_text =~
                /(<ref\b[^<>]*>\s*\[?www\w*\.)(?![^<>[\]{|}]*\[\w*:?\/\/)/ )
            {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 63
###########################################################################

sub error_063_html_text_style_elements_small_ref_sub_sup {
    my $error_code = 63;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $lc_text;
            my $pos       = -1;

            if ( index( $test_text, '<small>' ) > -1 ) {
                $pos = index( $test_text, '</small></ref>' )  if ( $pos == -1 );
                $pos = index( $test_text, '</small> </ref>' ) if ( $pos == -1 );
                $pos = index( $test_text, '<sub><small>' )    if ( $pos == -1 );
                $pos = index( $test_text, '<sub> <small>' )   if ( $pos == -1 );
                $pos = index( $test_text, '<sup><small>' )    if ( $pos == -1 );
                $pos = index( $test_text, '<sup> <small>' )   if ( $pos == -1 );

                $pos = index( $test_text, '<small><ref' )   if ( $pos == -1 );
                $pos = index( $test_text, '<small> <ref' )  if ( $pos == -1 );
                $pos = index( $test_text, '<small><sub>' )  if ( $pos == -1 );
                $pos = index( $test_text, '<small> <sub>' ) if ( $pos == -1 );

                #$pos = index( $test_text, '<small><sup>' )  if ( $pos == -1 );
                #$pos = index( $test_text, '<small> <sup>' ) if ( $pos == -1 );

                if ( $pos > -1 ) {
                    error_register( $error_code, substr( $text, $pos, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 64
###########################################################################

sub error_064_link_equal_linktext {
    my $error_code = 64;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $temp_text = $text;

            # OK (MUST) TO HAVE IN TIMELINE
            $temp_text =~ s/<timeline>(.*?)<\/timeline>//sg;

            # Account for [[foo_foo|foo foo]] by removing all _.
            $temp_text =~ tr/_/ /;

            # Account for [[Foo|foo]] and [[foo|Foo]] by capitalizing the
            # the first character after the [ and |.  But, do only on
            # non-wiktionary projects
            if ( $project !~ /wiktionary/ ) {
                $temp_text =~ s/\[\[\s*([\w])/\[\[\u$1/g;
                $temp_text =~ s/\[\[\s*([^|:\]]*)\s*\|\s*(.)/\[\[$1\|\u$2/g;

                # Account for [[Foo|''Foo'']] and [[Foo|'''Foo''']]
                $temp_text =~
                  s/\[\[\s*([^|:\]]*)\s*\|\s*('{2,})\s*(.)/\[\[$1\|$2\u$3/g;
            }

            if ( $temp_text =~ /(\[\[\s*([^|:]*)\s*\|\2\s*[.,]?\s*\]\])/ ) {
                my $found_text = $1;
                error_register( $error_code, $found_text );
            }

            # Account for [[Foo|''Foo'']] and [[Foo|'''Foo''']]
            elsif (
                $temp_text =~ /(\[\[\s*([^|:]*)\s*\|'{2,}\2\s*'{2,}\s*\]\])/ )
            {
                my $found_text = $1;
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 65
###########################################################################

sub error_065_image_description_with_break {
    my $error_code = 65;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text = q{};
            foreach (@Images_all) {

                if ( $_ =~ /<br([ ]+)?(\/)?([ ]+)?>([ ])?(\||\])/i ) {
                    if ( $found_text eq q{} ) {
                        $found_text = $_;
                    }
                }
            }
            if ( $found_text ne q{} ) {
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 66
###########################################################################

sub error_066_image_description_with_full_small {
    my $error_code = 66;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text = q{};
            foreach (@Images_all) {

                if (    $_ =~ /<small([ ]+)?(\/)?([ ]+)?>([ ])?(\||\])/i
                    and $_ =~ /\|([ ]+)?<small/i )
                {
                    if ( $found_text eq q{} ) {
                        $found_text = $_;
                    }
                }
            }
            if ( $found_text ne q{} ) {
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 67
###########################################################################

sub error_067_reference_after_punctuation {
    my $error_code = 67;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = lc($text);
            if ( $Template_list[$error_code][0] ne '-9999' ) {

                my @ack = @{ $Template_list[$error_code] };

                for my $temp (@ack) {
                    $test_text =~ s/($temp)<ref[ >]//sg;
                }

                if ( $test_text =~ /[ ]{0,2}(\.|,|\?|:|!|;)[ ]{0,2}<ref[ >]/ ) {
                    error_register( $error_code,
                        substr( $test_text, $-[0], 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 68
###########################################################################

sub error_068_link_to_other_language {
    my $error_code = 68;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Links_all) {

                my $current_link = $_;
                foreach (@INTER_LIST) {
                    if ( $current_link =~ /^\[\[([ ]+)?:([ ]+)?$_:/i ) {
                        error_register( $error_code, $current_link );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 69
###########################################################################

sub error_069_isbn_wrong_syntax {
    my ($found_text) = @_;
    my $error_code = 69;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( ( $page_namespace == 0 or $page_namespace == 104 )
            and $found_text ne q{} )
        {
            error_register( $error_code, $found_text );
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Links_all) {

                if ( index( $_, '[[|' ) > -1 ) {
                    my $pos = index( $_, '[[|' );
                    error_register( $error_code, substr( $_, $pos, 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 75
###########################################################################

sub error_075_indented_list {
    my $error_code = 75;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and ( $text =~ /:\*/ or $text =~ /:#/ ) )
        {
            my $list = 0;

            foreach (@Lines) {

                if ( index( $_, q{*} ) == 0 or index( $_, q{#} ) == 0 ) {
                    $list = 1;
                }
                elsif ( $list == 1
                    and ( $_ ne q{} and index( $_, q{:} ) != 0 ) )
                {
                    $list = 0;
                }

                if ( $list == 1
                    and ( index( $_, ':*' ) == 0 or index( $_, ':#' ) == 0 ) )
                {
                    error_register( $error_code, substr( $_, 0, 40 ) );
                }
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Links_all) {

                if ( $_ =~ /^\[\[([^\|]+)%20([^\|]+)/i ) {
                    error_register( $error_code, $_ );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 77
###########################################################################

sub error_077_image_description_with_partial_small {
    my $error_code = 77;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Images_all) {

                if ( $_ =~ /<small([ ]+)?(\/|\\)?([ ]+)?>([ ])?/i
                    and not $_ =~ /\|([ ]+)?<([ ]+)?small/ )
                {
                    error_register( $error_code, $_ );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 78
###########################################################################

sub error_078_reference_double {
    my $error_code = 78;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text      = $lc_text;
            my $number_of_refs = 0;
            my $pos_first      = -1;
            my $pos_second     = -1;
            while ( $test_text =~ /<references[ ]?\/>/g ) {
                my $pos = pos($test_text);

                $number_of_refs++;
                $pos_first = $pos
                  if ( $pos_first == -1 and $number_of_refs == 1 );
                $pos_second = $pos
                  if ( $pos_second == -1 and $number_of_refs == 2 );
            }

            if ( $number_of_refs > 1 ) {
                $test_text = $text;
                $test_text =~ s/\n/ /g;
                my $found_text = substr( $test_text, 0, $pos_first );
                $found_text = text_reduce_to_end( $found_text, 40 );
                my $found_text2 = substr( $test_text, 0, $pos_second );
                $found_text2 = text_reduce_to_end( $found_text2, 40 );
                $found_text = $found_text . '<br>' . $found_text2;
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 80
###########################################################################

sub error_080_external_link_with_line_break {
    my $error_code = 80;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $pos_start_old = 0;
            my $end_search    = 0;
            my $test_text     = $lc_text;

            while ( $end_search == 0 ) {
                my $pos_start   = 0;
                my $pos_start_s = 0;
                my $pos_end     = 0;
                $end_search = 1;

                $pos_start   = index( $test_text, '[http://',  $pos_start_old );
                $pos_start_s = index( $test_text, '[https://', $pos_start_old );
                if ( ( $pos_start_s < $pos_start ) and ( $pos_start_s > -1 ) ) {
                    $pos_start = $pos_start_s;
                }
                $pos_end = index( $test_text, ']', $pos_start );

                if ( $pos_start > -1 and $pos_end > -1 ) {

                    $end_search    = 0;
                    $pos_start_old = $pos_end;

                    my $weblink =
                      substr( $test_text, $pos_start, $pos_end - $pos_start );

                    if ( $weblink =~ /\n/ ) {
                        error_register( $error_code,
                            substr( $weblink, 0, 40 ) );
                    }
                }
            }
        }
    }
    return ();
}

###########################################################################
## ERROR 81
###########################################################################

sub error_081_ref_double {
    my $error_code = 81;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $number_of_ref = @Ref;
            foreach my $i ( 0 .. $number_of_ref - 2 ) {

                foreach my $j ( $i + 1 .. $number_of_ref - 1 ) {

                    if ( $Ref[$i] eq $Ref[$j] ) {
                        error_register( $error_code,
                            substr( $Ref[$i], 0, 40 ) );
                    }
                }
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            foreach (@Links_all) {

                my $current_link = $_;
                foreach (@FOUNDATION_PROJECTS) {
                    if (   $current_link =~ /^\[\[([ ]+)?$_:/i
                        or $current_link =~ /^\[\[([ ]+)?:([ ]+)?$_:/i )
                    {
                        error_register( $error_code, $current_link );
                    }
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 83
###########################################################################

sub error_083_headline_only_three_and_later_level_two {
    my $error_code = 83;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $Headlines[0]
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {
            if ( $Headlines[0] =~ /===/ ) {

                my $found_level_two = 'no';
                foreach (@Headlines) {
                    if ( $_ =~ /^==[^=]/ ) {
                        $found_level_two = 'yes';    #found level two (error 83)
                    }
                }
                if ( $found_level_two eq 'yes' ) {
                    error_register( $error_code, $Headlines[0] );
                }
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $Headlines[0]
            and ( $page_namespace == 0 or $page_namespace == 104 ) )
        {

            my $section_text = q{};
            my @my_lines = split( /\n/, $text_original );
            my @my_headlines;
            my @my_section;

            foreach (@my_lines) {
                my $current_line = $_;

                if (    ( substr( $current_line, 0, 1 ) eq '=' )
                    and ( $text =~ /\Q$current_line\E/ ) )
                {
                    push( @my_section, $section_text );
                    $section_text = q{};
                    push( @my_headlines, $current_line );
                }
                $section_text = $section_text . $_ . "\n";
            }
            push( @my_section, $section_text );

            my $number_of_headlines = @my_headlines;

            for ( my $i = 0 ; $i < $number_of_headlines - 1 ; $i++ ) {

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
                            if ( $length > 1 ) {

                                if ( $test_section eq q{} )

         #                                    and $text =~ /$my_headlines[$i]/ )
                                {
                                    error_register( $error_code,
                                        $my_headlines[$i] );
                                }
                            }
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if (
                $lc_text =~ /<noinclude>\s*<\/noinclude>|
                           <onlyinclude>\s*<\/onlyinclude|
                           <includeonly>\s*<\/includeonly>|
                           <center>\s*<\/center>|
                           (<gallery[^>]*(?:\/>|>(?:\s|&nbsp;)*<\/gallery>))|
                           <ref>\s*<\/ref>|
                           <span>\s*<\/span>|
                           <div>\s*<\/div>
                           /x
              )
            {
                my $found_text = substr( $text, $-[0], 40 );
                $found_text =~ s/\n//g;
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 86
###########################################################################

sub error_086_link_with_two_brackets_to_external_source {
    my $error_code = 86;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $text;
            if ( $test_text =~ /(\[\[\s*https?:\/\/[^\]:]*)/i ) {
                error_register( $error_code, substr( $1, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 87
###########################################################################

sub error_087_html_named_entities_without_semicolon {
    my $error_code = 87;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if (   $page_namespace == 0
            or $page_namespace == 6
            or $page_namespace == 104 )
        {

            my $pos       = -1;
            my $test_text = $text;

            # IMAGE'S CAN HAVE HTML NAMED ENTITES AS PART OF THEIR FILENAME
            foreach (@Images_all) {
                $test_text =~ s/\Q$_\E//sg;
            }

            $test_text = lc($test_text);

            # REFS USE '&' FOR INPUT
            $test_text =~ s/<ref(.*?)>https?:(.*?)<\/ref>//sg;
            $test_text =~ s/https?:(.*?)\n//g;

            foreach (@HTML_NAMED_ENTITIES) {
                if ( $test_text =~ /&$_[^;] /g ) {
                    $pos = $-[0];
                }
            }

            if ( $pos > -1 ) {
                error_register( $error_code, substr( $test_text, $pos, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 88
###########################################################################

sub error_088_defaultsort_with_first_blank {
    my $error_code = 88;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {

        if (    ( $page_namespace == 0 or $page_namespace == 104 )
            and $project ne 'arwiki'
            and $project ne 'hewiki'
            and $project ne 'plwiki'
            and $project ne 'jawiki'
            and $project ne 'yiwiki'
            and $project ne 'zhwiki' )
        {

            # Is DEFAULTSORT found in article?
            my $isDefaultsort     = -1;
            my $current_magicword = q{};
            foreach ( @{$Magicword_defaultsort} ) {
                if ( $isDefaultsort == -1 and index( $text, $_ ) > -1 ) {
                    $isDefaultsort = index( $text, $_ );
                    $current_magicword = $_;
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
    }

    return ();
}

###########################################################################
## ERROR 89
###########################################################################

sub error_089_defaultsort_with_no_space_after_comma {
    my $error_code = 89;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            # Is DEFAULTSORT found in article?
            my $isDefaultsort     = -1;
            my $current_magicword = q{};
            foreach ( @{$Magicword_defaultsort} ) {
                if ( $isDefaultsort == -1 and index( $text, $_ ) > -1 ) {
                    $isDefaultsort = index( $text, $_ );
                    $current_magicword = $_;
                }
            }

            if ( $isDefaultsort > -1 ) {
                my $pos2 = index( substr( $text, $isDefaultsort ), '}}' );
                my $test_text = substr( $text, $isDefaultsort, $pos2 );

                if ( $test_text =~
/DEFAULTSORT:([A-Za-z'-.]+),([A-Za-z'-.]+)(\s*)([A-Za-z0-9-.]*)/
                  )
                {
                    error_register( $error_code, $test_text );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 90
###########################################################################

sub error_090_Internal_link_written_as_an_external_link {
    my $error_code = 90;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $lc_text =~ /($ServerName\/wiki)/i ) {
                error_register( $error_code, substr( $1, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 91
###########################################################################

sub error_091_Interwiki_link_written_as_an_external_link {
    my $error_code = 91;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $test_text = $lc_text;
            $test_text =~ s/($ServerName)//ig;
            if ( $test_text =~ /([a-z]{2,3}\.wikipedia\.org\/wiki)/i ) {
                error_register( $error_code, substr( $1, 0, 40 ) );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 92
###########################################################################

sub error_092_headline_double {
    my $error_code = 92;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            my $found_text          = q{};
            my $number_of_headlines = @Headlines;
            for ( my $i = 0 ; $i < $number_of_headlines - 1 ; $i++ ) {
                my $first_headline   = $Headlines[$i];
                my $secound_headline = $Headlines[ $i + 1 ];

                if ( $first_headline eq $secound_headline ) {
                    $found_text = $Headlines[$i];
                }
            }
            if ( $found_text ne q{} ) {
                error_register( $error_code, $found_text );
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 93
###########################################################################

sub error_093_double_http {
    my $error_code = 93;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $lc_text =~ /(https?:[\/]{0,2}https?:)/ ) {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
            }
        }
    }
    return ();
}

###########################################################################
## ERROR 94
###########################################################################

sub error_094_ref_no_correct_match {
    my $error_code = 94;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

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
        }
    }

    return ();
}

###########################################################################
## ERROR 95
###########################################################################

sub error_095_user_signature {
    my $error_code = 95;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $Draft_regex ne q{} ) {
                if ( $lc_text =~ /($User_regex|$Draft_regex)/i ) {
                    error_register( $error_code, substr( $text, $-[0], 40 ) );
                }
            }
            else {
                if ( $lc_text =~ /($User_regex)/i ) {
                    error_register( $error_code, substr( $text, $-[0], 40 ) );
                }
            }
        }
    }

    return ();
}
###########################################################################
## ERROR 96
###########################################################################

sub error_096_toc_after_first_headline {
    my $error_code = 96;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $lc_text =~ /$Template_regex[96]__toc__/ ) {
                my $toc_pos = $-[0];
                my $headline_pos = index( $text, $Headlines[0] );
                if ( $toc_pos > $headline_pos ) {
                    error_register( $error_code, substr( $text, $-[0], 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 97
###########################################################################

sub error_097_toc_has_material_after_it {
    my $error_code = 97;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $lc_text =~ /$Template_regex[97]__toc__/ ) {
                my $toc_pos = $-[0];
                my $headline_pos = index( $text, $Headlines[0] );
                if ( ( $headline_pos - $toc_pos ) > 40 and $-[0] > -1 ) {
                    error_register( $error_code, substr( $text, $-[0], 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 98
###########################################################################

sub error_098_sub_no_correct_end {
    my $error_code = 98;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $lc_text =~ /<sub>/ ) {
                my $sub_begin = 0;
                my $sub_end   = 0;

                $sub_begin = () = $lc_text =~ /<sub>/g;
                $sub_end   = () = $lc_text =~ /<\/sub>/g;

                if ( $sub_begin > $sub_end ) {
                    my $snippet = get_broken_tag( '<sub>', '</sub>' );
                    error_register( $error_code, $snippet );
                }
            }
        }
    }

    return ();
}
###########################################################################
## ERROR 99
###########################################################################

sub error_099_sup_no_correct_end {
    my $error_code = 99;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $lc_text =~ /<sup>/ ) {
                my $sup_begin = 0;
                my $sup_end   = 0;

                $sup_begin = () = $lc_text =~ /<sup>/g;
                $sup_end   = () = $lc_text =~ /<\/sup>/g;

                if ( $sup_begin > $sup_end ) {
                    my $snippet = get_broken_tag( '<sup>', '</sup>' );
                    error_register( $error_code, $snippet );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 100
###########################################################################

sub error_100_list_tag_no_correct_end {
    my $error_code = 100;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

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
        }
    }

    return ();
}

###########################################################################
## ERROR 101
###########################################################################

sub error_101_ordinal_numbers_in_sup {
    my $error_code = 101;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $lc_text =~ /\d<sup>/ ) {

                # REMOVE {{not a typo}} TEMPLATE
                $lc_text =~ s/\{\{not a typo\|[a-zA-Z0-9\<\>\/]*\}\}//g;
                if ( $lc_text =~ /\d<sup>(st|rd|th|nd)<\/sup>/ ) {
                    error_register( $error_code, substr( $text, $-[0], 40 ) );
                }
            }
        }
    }

    return ();
}

###########################################################################
## ERROR 102
###########################################################################

sub error_102_pmid_wrong_syntax {
    my $error_code = 102;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            # CHECK FOR SPACE BEFORE PMID AS URLS CAN CONTAIN PMID
            if ( $lc_text =~ / pmid\s*([-]|[:]|[#])\s*/g ) {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
            }
        }
    }

    return ();

}

###########################################################################
## ERROR 103
###########################################################################

sub error_103_pipe_magicword_in_wikilink {
    my $error_code = 103;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $lc_text =~ /\[\[([^\[\]]*)\{\{!\}\}([^\[\]]*)\]\]/g ) {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
            }
        }
    }

    return ();

}

###########################################################################
## ERROR 104
###########################################################################

sub error_104_quote_marks_in_refs {
    my $error_code = 104;

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        if ( $page_namespace == 0 or $page_namespace == 104 ) {

            if ( $text =~ /\<ref\sname\=\"\w+\>/gi ) {
                error_register( $error_code, substr( $text, $-[0], 40 ) );
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

    if ( $ErrorPriorityValue[$error_code] > 0 ) {
        foreach (@Lines) {
            my $current_line  = $_;
            my $current_line1 = $current_line;

            $current_line1 =~ s/\t//gi;
            $current_line1 =~ s/[ ]+/ /gi;
            $current_line1 =~ s/ $//gi;

            if ( $current_line =~ /==$/
                and not( $current_line1 =~ /^==/ )
                and index( $current_line, '</ref' ) == -1
                and ( $page_namespace == 0 or $page_namespace == 104 ) )
            {
                error_register( $error_code, substr( $current_line, 0, 40 ) );
            }
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
        $notice =~ s/\n//g;

        print "\t" . $error_code . "\t" . $title . "\t" . $notice . "\n";

        $Error_number_counter[$error_code] =
          $Error_number_counter[$error_code] + 1;
        $Error_counter = $Error_counter + 1;

        #insert_into_db( $error_code, $notice );
    }
    else {
        print $title . " is in whitelist with error: " . $error_code . "\n";
    }

    return ();
}

######################################################################}

sub insert_into_db {
    my ( $code, $notice ) = @_;
    my ( $table_name, $date_found, $article_title );

    $notice = substr( $notice, 0, 100 );    # Truncate notice.
    $article_title = $title;

    # Problem: sql-command insert, apostrophe ' or backslash \ in text
    $article_title =~ s/\\/\\\\/g;
    $article_title =~ s/'/\\'/g;
    $notice =~ s/\\/\\\\/g;
    $notice =~ s/'/\\'/g;

    $notice =~ s/\&/&amp;/g;
    $notice =~ s/</&lt;/g;
    $notice =~ s/>/&gt;/g;
    $notice =~ s/\"/&quot;/g;

    if ( $Dump_or_Live eq 'live' or $Dump_or_Live eq 'delay' ) {
        $table_name = 'cw_error';
        $date_found = strftime( '%F %T', gmtime() );
    }
    else {
        $table_name = 'cw_dumpscan';
        $date_found = $time_found;
    }

    my $sql_text =
        "INSERT IGNORE INTO "
      . $table_name
      . " VALUES ( '"
      . $project . "', '"
      . $article_title . "', "
      . $code . ", '"
      . $notice
      . "', 0, '"
      . $time_found . "' );";

    my $sth = $dbh->prepare($sql_text);
    $sth->execute;

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

sub print_line {

    # Print a line for better structure of output
    if ( $Dump_or_Live ne 'list' ) {
        print '-' x 80;
        print "\n";
    }

    return ();
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
    print STDERR "To scan a dump:\n"
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

my ( $load_mode, $dump_date_for_output );

my @Options = (
    'load=s'       => \$load_mode,
    'project|p=s'  => \$project,
    'database|D=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
    'dumpfile=s'   => \$DumpFilename,
    'listfile=s'   => \$ListFilename,
    'article=s'    => \$ArticleName,
    'tt'           => \$Template_Tiger,
    'check'        => \$CheckOnlyOne,
);

if (
    !GetOptions(
        'c=s' => sub {
            my $f = IO::File->new( $_[1], '<:encoding(UTF-8)' )
              or die( "Can't open " . $_[1] . "\n" );
            local ($/);
            my $s = <$f>;
            $f->close();
            my ( $Success, $RemainingArgs ) =
              GetOptionsFromString( $s, @Options );
            die unless ( $Success && !@$RemainingArgs );
        },
        @Options,
    )
  )
{
    usage();
    exit(1);
}

if ( !defined($project) ) {
    usage();
    die("$0: No project name, for example: \"-p dewiki\"\n");
}

if ( defined($DumpFilename) ) {
    $Dump_or_Live = 'dump';

    # GET DATE FROM THE DUMP FILENAME
    $dump_date_for_output = $DumpFilename;
    $dump_date_for_output =~
s/^(?:.*\/)?\Q$project\E-(\d{4})(\d{2})(\d{2})-pages-articles\.xml(.*?)$/$1-$2-$3/;
}
elsif ( $load_mode eq 'live' ) {
    $Dump_or_Live = 'live';
}
elsif ( $load_mode eq 'delay' ) {
    $Dump_or_Live = 'delay';
}
elsif ( $load_mode eq 'list' ) {
    $Dump_or_Live = 'list';
}
elsif ( $load_mode eq 'article' ) {
    $Dump_or_Live = 'article';
}
else {
    die("No load name, for example: \"-l live\"\n");
}

# OPEN TEMPLATETIGER FILE
if ( $Template_Tiger == 1 ) {
    if ( !$dump_date_for_output ) {
        $dump_date_for_output = 'list';
    }
    $TTFile = File::Temp->new(
        DIR      => $TTDIRECTORY,
        TEMPLATE => $project . '-' . $dump_date_for_output . '-XXXX',
        SUFFIX   => '.txt',
        UNLINK   => 0
    );
    $TTFilename =
      $TTDIRECTORY . '/' . $project . '-' . $dump_date_for_output . '.txt';
    binmode( $TTFile, ":encoding(UTF-8)" );
}

if ( $Dump_or_Live ne 'article' ) {
    print_line();
    two_column_display( 'Start time:',
        ( strftime "%a %b %e %H:%M:%S %Y", localtime ) );
    $time_found = strftime( '%F %T', gmtime() );
    two_column_display( 'Project:',   $project );
    two_column_display( 'Scan type:', $Dump_or_Live . " scan" );
}

open_db();
clearDumpscanTable() if ( $Dump_or_Live eq 'dump' );
getErrors();
readMetadata();
readTemplates();

# MAIN ROUTINE - SCAN PAGES FOR ERRORS
scan_pages();

updateDumpDate($dump_date_for_output) if ( $Dump_or_Live eq 'dump' );
#update_table_cw_error_from_dump()     if ( $Dump_or_Live ne 'article' );
#delete_done_article_from_db()         if ( $Dump_or_Live ne 'article' );

# CLOSE TEMPLATETIGER FILE
if ( defined($TTFile) ) {

    # Move Templatetiger file to spool.
    $TTFile->close() or die( $! . "\n" );
    if ( !rename( $TTFile->filename(), $TTFilename ) ) {
        die(    "Couldn't rename temporary Templatetiger file from "
              . $TTFile->filename() . ' to '
              . $TTFilename
              . "\n" );
    }
    if ( !chmod( 0664, $TTFilename ) ) {
        die( "Couldn't chmod 664 Templatetiger file " . $TTFilename . "\n" );
    }
    undef($TTFile);
}

close_db();

if ( $Dump_or_Live ne 'article' ) {
    print_line();
    two_column_display( 'Articles checked:', $artcount );
    two_column_display( 'Errors found:',     ++$Error_counter );

    $time_end = time() - $time_start;
    $time_end = sprintf "%d hours, %d minutes and %d seconds",
      ( gmtime $time_end )[ 2, 1, 0 ];
    two_column_display( 'Program run time:', $time_end );
    two_column_display( 'PROGRAM FINISHED',  '' );
    print_line();
}
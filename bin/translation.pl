#!/usr/bin/env perl

###########################################################################
##
##         FILE: translation.pl
##
##        USAGE: ./translation.pl -c checkwiki.cfg
##
##  DESCRIPTION: Updates translations and errors in the database
##
##       AUTHOR: Stefan Kühn, Bryan White
##      LICENCE: GPLv3
##      VERSION: 11/26/2013
##
###########################################################################

use strict;
use warnings;
use utf8;

use DBI;
use Encode;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use LWP::UserAgent;
use URI::Escape;

binmode( STDOUT, ":encoding(UTF-8)" );

our $OUTPUT_DIRECTORY       = "/data/project/checkwiki/public_html/Translation";
our $TRANSLATION_FILE       = 'translation.txt';
our $TOP_PRIORITY_SCRIPT    = 'Top priority';
our $MIDDLE_PRIORITY_SCRIPT = 'Middle priority';
our $LOWEST_PRIORITY_SCRIPT = 'Lowest priority';

our @Projects;
our $project;
our @ErrorDescription;
our $Number_of_error_description = 113;

our $TranslationFile;
our @Whitelist;
our @Template;

our $Top_priority_project    = q{};
our $Middle_priority_project = q{};
our $Lowest_priority_project = q{};

our $StartText;
our $DescriptionText;
our $CategoryText;

#Database configuration
our $DbName;
our $DbServer;
our $DbUsername;
our $DbPassword;
our $dbh;

#------------------

our %TranslationLocation = (
    'afwiki'      => 'Wikipedia:WikiProject Check Wikipedia/Translation',
    'arwiki'      => 'ﻮﻴﻜﻴﺒﻳﺪﻳﺍ:ﻒﺤﺻ_ﻮﻴﻜﻴﺒﻳﺪﻳﺍ/ﺕﺮﺠﻣﺓ',
    'arzwiki'     => 'ويكيبيديا:تشيك ويكيبيديا/ترجمه', 
    'bewiki'      => 'Вікіпедыя:WikiProject Check Wikipedia/Translation',
    'cawiki'      => 'Viquipèdia:WikiProject Check Wikipedia/Translation',
    'cswiki'      => 'Wikipedie:WikiProjekt Check Wikipedia/Translation',
    'cywiki'      => 'Wicipedia:WikiProject Check Wikipedia/Translation',
    'dawiki'      => 'Wikipedia:WikiProjekt Check Wikipedia/Oversættelse',
    'dewiki'      => 'Wikipedia:WikiProjekt Syntaxkorrektur/Übersetzung',
    'enwiki'      => 'Wikipedia:WikiProject Check Wikipedia/Translation',
    'enwiktionary' => 'Wiktionary:WikiProject_Check_Wikipedia/Translation',
    'eowiki'      => 'Projekto:Kontrolu Vikipedion/Tradukado',
    'eswiki'      => 'Wikiproyecto:Check Wikipedia/Translation',
    'fawiki'      => 'ویکی‌پدیا:ویکی‌پروژه_تصحیح_ویکی‌پدیا/ترجمه',
    'fiwiki'      => 'Wikiprojekti:Check Wikipedia/Translation',
    'frwiki'      => 'Projet:Correction syntaxique/Traduction',
    'fywiki'      =>
              'Meidogger:Stefan Kühn/WikiProject Check Wikipedia/Translation',
    'hewiki'      => 'ויקיפדיה:Check_Wikipedia/Translation',
    'huwiki'      => 'Wikipédia:Ellenőrzőműhely/Fordítás',
    'idwiki'      => 'Wikipedia:ProyekWiki Cek Wikipedia/Terjemahan',
    'iswiki'      => 'Wikipedia:WikiProject Check Wikipedia/Translation',
    'itwiki'      => 'Wikipedia:WikiProjekt Check Wikipedia/Translation',
    'jawiki'      => 'プロジェクト:ウィキ文法のチェック/Translation',
    'lawiki'      => 'Vicipaedia:WikiProject Check Wikipedia/Translation',
    'lvwiki'      => 'Vikiprojekts:Check_Wikipedia/Tulkojums',
    'ndswiki'     => 'Wikipedia:Wikiproject Check Wikipedia/Translation',
    'nds_nlwiki'  => 'Wikipedie:WikiProject Check Wikipedia/Translation',
    'nlwiki'      => 'Wikipedia:Wikiproject/Check Wikipedia/Vertaling',
    'nowiki'      => 'Wikipedia:WikiProject Check Wikipedia/Translation',
    'pdcwiki'     => 'Wikipedia:WikiProject Check Wikipedia/Translation',
    'plwiki'      => 'Wikiprojekt:Check Wikipedia/Tłumaczenie',
    'ptwiki'      => 'Wikipedia:Projetos/Check Wikipedia/Tradução',
    'ruwiki'      => 'Проект:Check Wikipedia/Перевод',
    'rowiki'      => 'Wikipedia:WikiProject Check Wikipedia/Translation',
    'skwiki'      => 'Wikipédia:WikiProjekt Check Wikipedia/Translation',
    'svwiki'      => 'Wikipedia:Projekt wikifiering/Syntaxfel/Translation',
    'svwiktionary'=> 'Wiktionary:Projekt/Syntaxfel/Translation',
    'trwiki'      => 'Vikipedi:Vikipedi proje kontrolü/Çeviri',
    'ukwiki'      => 'Вікіпедія:Проект:Check Wikipedia/Translation',
    'yiwiki'      => 'װיקיפּעדיע:קאנטראלירן_בלעטער/Translation',
    'zhwiki'      => '维基百科:错误检查专题/翻译',
);

##########################################################################
## MAIN PROGRAM
##########################################################################

my @Options = (
    'database|d=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
);

GetOptions(
    'c=s' => sub {
        my $f = IO::File->new( $_[1], '<' )
          or die( "Can't open " . $_[1] . "\n" );
        local ($/);
        my $s = <$f>;
        $f->close();
        my ( $Success, $RemainingArgs ) = GetOptionsFromString( $s, @Options );
        die unless ( $Success && !@$RemainingArgs );
    }
);

#--------------------

open_db();
get_projects();

foreach (@Projects) {
$project = $_; 

    print "\n\n";
    two_column_display( 'Working on:', $project );
    get_error_description();
    $TranslationFile = get_translation_page();
#    if ( $TranslationFile ne q{} ) {
        load_text_translation();
        clearWhitelistTable();
        add_whitelist_to_db();
        clearTemplateTable();
        add_templates_to_db();
        output_text_translation_wiki();
#    }
    output_errors_desc_in_db();

}

close_db();

##########################################################################
## OPEN DATABASE
##########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : q{} ),
        $DbUsername,
        $DbPassword,
        {
            RaiseError        => 1,
            AutoCommit        => 1,
            mysql_enable_utf8mb4 => 1
        }
    ) or die( "Could not connect to database: " . DBI::errstr() . "\n" );

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
## GET ERROR DESCRIPTION
###########################################################################

sub get_error_description {

    two_column_display( 'load:', 'all error description from script' );

    my $sql_text =
      "SELECT COUNT(*) FROM cw_overview_errors WHERE project = 'enwiki';";
    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    $sql_text =
      "SELECT prio, name, text FROM cw_overview_errors WHERE project = 'enwiki';";
    $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my @output;

    foreach my $i ( 1 .. $Number_of_error_description ) {
        @output                  = $sth->fetchrow();
        $ErrorDescription[$i][0] = $output[0];
        $ErrorDescription[$i][1] = $output[1];
        $ErrorDescription[$i][2] = $output[2];
    }

    # set all known error description to a basic level
    foreach my $i ( 1 .. $Number_of_error_description ) {
        $ErrorDescription[$i][3]  = 0;
        $ErrorDescription[$i][4]  = -1;
        $ErrorDescription[$i][5]  = q{};
        $ErrorDescription[$i][6]  = q{};
        $ErrorDescription[$i][7]  = 0;
        $ErrorDescription[$i][8]  = 0;
        $ErrorDescription[$i][9]  = q{};
        $ErrorDescription[$i][10] = q{};
    }

    two_column_display( '# of error descriptions:',
        $Number_of_error_description . ' in script' );

    return ();
}

###########################################################################
### GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
############################################################################

sub get_projects {

    print "Load projects from db\n";
    my $result = q();
    my $sth = $dbh->prepare('SELECT project FROM cw_overview ORDER BY project;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my $project_counter = 0;
    while ( my $arrayref = $sth->fetchrow_arrayref() ) {

        foreach (@$arrayref) {
            $result = $_;
        }

        push( @Projects, $result );
        $project_counter++;
    }

    return ();
}

##########################################################################
## INSERT TRANSLATION PAGE
##########################################################################

sub insert_into_projects {
    my ($page) = @_;

    my $sql_text =
        "UPDATE cw_overview SET Translation_Page='"
      . $page
      . "' WHERE project='"
      . $project . "';";
    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

}

###########################################################################
### GET TRANSLATION PAGE FROM DATABASE
############################################################################

sub get_translation_page {

    my $sth = $dbh->prepare(
        'SELECT translation_page FROM cw_overview WHERE project= ?');
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    my $file = $sth->fetchrow();
    $file = q{} if ( !defined $file );

    return ($file);
}

##########################################################################
## LOAD TEXT TRANSLATION
##########################################################################

sub load_text_translation {

    my $translation_input;

    #my $translation_page = $TranslationLocation{$project};
    my $translation_page = $TranslationFile;

    two_column_display( 'Translation input:', $translation_page );
    insert_into_projects($translation_page);
    $translation_input = raw_text($translation_page);
    $translation_input = replace_special_letters($translation_input);

    my $input_text = q{};

    # start_text
    $input_text =
      get_translation_text( $translation_input, 'start_text_' . $project . '=',
        'END' );
    $StartText = $input_text;

    # description_text
    $input_text = get_translation_text( $translation_input,
        'description_text_' . $project . '=', 'END' );
    $DescriptionText = $input_text;

    # category_text
    $input_text =
      get_translation_text( $translation_input, 'category_001=', 'END' );
    $CategoryText = $input_text;

    # priority
    $input_text = get_translation_text( $translation_input,
        'top_priority_' . $project . '=', 'END' );
    $Top_priority_project = $input_text if ( $input_text ne q{} );
    $input_text = get_translation_text( $translation_input,
        'middle_priority_' . $project . '=', 'END' );
    $Middle_priority_project = $input_text if ( $input_text ne q{} );
    $input_text = get_translation_text( $translation_input,
        'lowest_priority_' . $project . '=', 'END' );
    $Lowest_priority_project = $input_text if ( $input_text ne q{} );

    # find error description
    foreach my $i ( 1 .. $Number_of_error_description ) {
        my $current_error_number = 'error_';
        $current_error_number = $current_error_number . '0' if ( $i < 10 );
        $current_error_number = $current_error_number . '0' if ( $i < 100 );
        $current_error_number = $current_error_number . $i;

        # template
        $Template[$i] =
          get_translation_text( $translation_input,
            $current_error_number . '_templates_' . $project . '=', 'END' );
        
        # abbreviations 
        if (  $Template[$i] eq q{} ) {
            $Template[$i] =  get_translation_text( $translation_input,
            $current_error_number . '_abbreviations_' . $project . '=', 'END' );
        }

        # whitelist
        $Whitelist[$i] =
          get_translation_text( $translation_input,
            $current_error_number . '_whitelistpage_' . $project . '=', 'END' );

        # Priority
        $ErrorDescription[$i][4] = get_translation_text( $translation_input,
            $current_error_number . '_prio_' . $project . '=', 'END' );

        if ( $ErrorDescription[$i][4] ne q{} ) {

            # if a translation was found
            $ErrorDescription[$i][4] = int( $ErrorDescription[$i][4] );
        }
        else {
            # if no translation was found
            $ErrorDescription[$i][4] = $ErrorDescription[$i][0];
        }

        if ( $ErrorDescription[$i][4] == -1 ) {

            # in project unkown then use prio from script
            $ErrorDescription[$i][4] = $ErrorDescription[$i][0];
        }

        $ErrorDescription[$i][5] = get_translation_text( $translation_input,
            $current_error_number . '_head_' . $project . '=', 'END' );
        $ErrorDescription[$i][6] = get_translation_text( $translation_input,
            $current_error_number . '_desc_' . $project . '=', 'END' );

    }

    return ();
}

###########################################################################
## DELETE WHITELIST ARTICLES FROM DATABASE
###########################################################################

sub clearWhitelistTable {

    my $sth = $dbh->prepare('DELETE FROM cw_whitelist WHERE Project = ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    return ();

}

###########################################################################
## ADD WHITELIST ARTICLES TO DATABASE
###########################################################################

sub add_whitelist_to_db {

    my $error_input;

    $dbh->{AutoCommit} = 0;
    foreach my $error ( 1 .. $Number_of_error_description ) {
        my $error_page = $Whitelist[$error];
       
        if ( $error_page ne q{} ) {
            $error_input = raw_text($error_page);
            $error_input = replace_special_letters($error_input);

            while ( $error_input =~ /\* \[\[/g ) {
                my $pos_start = pos($error_input) - 4;
                my $current = substr( $error_input, $pos_start );
                $current =~ /\* \[\[([^\[]*)\]\]/;
                my $title = $1;

                if ( defined($title) ) {
                    my $sth = $dbh->prepare(
'INSERT IGNORE INTO cw_whitelist (project, title, error, ok ) VALUES (?, ?, ?, 1)'
                    );
                    $sth->execute( $project, $title, $error )
                      or die "Cannot execute: " . $sth->errstr . "\n";
                }
            }
            $dbh->commit or die "Cannot commit\n";
        }
    }

    $dbh->{AutoCommit} = 1;
    return ();
}

###########################################################################
## DELETE TEMPLATES FROM DATABASE
###########################################################################

sub clearTemplateTable {

    my $sth = $dbh->prepare('DELETE FROM cw_template WHERE Project = ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    return ();

}

###########################################################################
## ADD TEMPLATES TO DATABASE
###########################################################################

sub add_templates_to_db {

    foreach my $error ( 1 .. $Number_of_error_description ) {

        if ( defined( $Template[$error] ) ) {

            my @array = split( /\n/, $Template[$error] );
            foreach (@array) {

                if ( $_ ne '' ) {

                    $_ =~ s/^\s+|\s+$//;

                    my $sth = $dbh->prepare(
'INSERT IGNORE INTO cw_template (project, templates, error ) VALUES (?, ?, ?)'
                    );
                    $sth->execute( $project, $_, $error )
                      or die "Cannot execute: " . $sth->errstr . "\n";
                }
            }
        }
    }

    return ();
}

###########################################################################
## OUTPUT ERROR DESCRIPTION TO DATABASE
###########################################################################

sub output_errors_desc_in_db {

    $dbh->{AutoCommit} = 0;
    foreach my $i ( 1 .. $Number_of_error_description ) {
        my $sql_headline = $ErrorDescription[$i][1];
        $sql_headline =~ s/'/\\'/g;
        my $sql_desc = $ErrorDescription[$i][2];
        $sql_desc =~ s/'/\\'/g;
        $sql_desc = substr( $sql_desc, 0, 3999 );
        my $sql_headline_trans = $ErrorDescription[$i][5];
        $sql_headline_trans =~ s/'/\\'/g;
        my $sql_desc_trans = $ErrorDescription[$i][6];
        $sql_desc_trans =~ s/'/\\'/g;
        $sql_desc = substr( $sql_desc_trans, 0, 3999 );

        # insert or update error
        my $sql_text = "UPDATE cw_overview_errors
        SET prio=" . $ErrorDescription[$i][4] . ",
        name='" . $sql_headline . "' ,
        text='" . $sql_desc . "',
        name_trans='" . $sql_headline_trans . "' ,
        text_trans='" . $sql_desc_trans . "'
        WHERE id = " . $i . "
        AND project = '" . $project . "'
        ;";

        #print "SQL_TEXT:" . $sql_text . "\n";
        my $sth = $dbh->prepare($sql_text)
          || die "Can not prepare statement: $DBI::errstr\n";
        my $x = $sth->execute;

        if ( $x ne '1' ) {
            two_column_display( 'new error:', 'description insert into db' );
            $sql_text =
"INSERT INTO cw_overview_errors (project, id, prio, name, text, name_trans, text_trans) VALUES ('"
              . $project . "', "
              . $i . ", "
              . $ErrorDescription[$i][4] . ", '"
              . $sql_headline . "' ,'"
              . $sql_desc . "','"
              . $sql_headline_trans . "' ,'"
              . $sql_desc_trans . "' );";
            $sth = $dbh->prepare($sql_text)
              || die "Can not prepare statement: $DBI::errstr\n";
            $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";
        }
    }

    $dbh->commit or die "Cannot commit\n";
    $dbh->{AutoCommit} = 0;
    return ();
}

###########################################################################
## GET TRANSLATION
###########################################################################

sub get_translation_text {
    my ( $translation_text, $start_tag, $end_tag ) = @_;

    my $pos_1 = index( $translation_text, $start_tag );
    my $pos_2 = index( $translation_text, $end_tag, $pos_1 );
    my $result = q{};

    if ( $pos_1 > -1 and $pos_2 > 0 ) {
        $result = substr( $translation_text, $pos_1, $pos_2 - $pos_1 );
        $result = substr( $result, index( $result, '=' ) + 1 );
        $result =~ s/^ //g;
        $result =~ s/ $//g;
    }

    return ($result);
}

###########################################################################
## OUTPUT TEXT TRANSLATION
###########################################################################

sub output_text_translation_wiki {

    my $filename = $OUTPUT_DIRECTORY . '/' . $project . '_' . $TRANSLATION_FILE;
    two_column_display( 'Output translation text to:',
        $project . '_' . $TRANSLATION_FILE );
    open TRANSLATION, ">:encoding(UTF-8)", $filename
      or die "unable to open: $filename\n";

    print TRANSLATION '<pre>' . "\n";
    print TRANSLATION
      ' new translation text under http://toolserver.org/~sk/checkwiki/'
      . $project . '/'
      . " (updated daily) \n";

    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# metadata' . "\n";
    print TRANSLATION '#########################' . "\n";

    print TRANSLATION ' project=' . $project . " END\n";
    print TRANSLATION ' category_001='
      . $CategoryText
      . " END  #for example: [[Category:Wikipedia]] \n";
    print TRANSLATION "\n";

    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# start text' . "\n";
    print TRANSLATION '#########################' . "\n";
    print TRANSLATION "\n";
    print TRANSLATION ' start_text_' . $project . '=' . $StartText . " END\n";

    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# description' . "\n";
    print TRANSLATION '#########################' . "\n";
    print TRANSLATION "\n";
    print TRANSLATION ' description_text_'
      . $project . '='
      . $DescriptionText
      . " END\n";

    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# priority' . "\n";
    print TRANSLATION '#########################' . "\n";
    print TRANSLATION "\n";

    print TRANSLATION ' top_priority_script=' . $TOP_PRIORITY_SCRIPT . " END\n";
    print TRANSLATION ' top_priority_'
      . $project . '='
      . $Top_priority_project
      . " END\n";
    print TRANSLATION ' middle_priority_script='
      . $MIDDLE_PRIORITY_SCRIPT
      . " END\n";
    print TRANSLATION ' middle_priority_'
      . $project . '='
      . $Middle_priority_project
      . " END\n";
    print TRANSLATION ' lowest_priority_script='
      . $LOWEST_PRIORITY_SCRIPT
      . " END\n";
    print TRANSLATION ' lowest_priority_'
      . $project . '='
      . $Lowest_priority_project
      . " END\n";
    print TRANSLATION "\n";
    print TRANSLATION " Please only translate the variables with _" . $project
      . " at the end of the name. Not _script= .\n";

    ################

    my $number_of_error_description_output = $Number_of_error_description;
    two_column_display( 'error description:',
        $number_of_error_description_output . ' error description total' );

    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# error description' . "\n";
    print TRANSLATION '#########################' . "\n";
    print TRANSLATION '# prio = -1 (unknown)' . "\n";
    print TRANSLATION '# prio = 0  (deactivated) ' . "\n";
    print TRANSLATION '# prio = 1  (top priority)' . "\n";
    print TRANSLATION '# prio = 2  (middle priority)' . "\n";
    print TRANSLATION '# prio = 3  (lowest priority)' . "\n";
    print TRANSLATION "\n";

    foreach my $i ( 1 .. $Number_of_error_description ) {

        my $current_error_number = 'error_';
        $current_error_number = $current_error_number . '0' if ( $i < 10 );
        $current_error_number = $current_error_number . '0' . $i
          if ( $i < 100 );
        print TRANSLATION ' '
          . $current_error_number
          . '_prio_script='
          . $ErrorDescription[$i][0]
          . " END\n";
        print TRANSLATION ' '
          . $current_error_number
          . '_head_script='
          . $ErrorDescription[$i][1]
          . " END\n";
        if ( $Whitelist[$i] =~ /[a-zA-z0-0]/ ) {
            print TRANSLATION ' '
              . $current_error_number
              . '_whitelist='
              . $Whitelist[$i]
              . " END\n";
        }
        print TRANSLATION ' '
          . $current_error_number
          . '_desc_script='
          . $ErrorDescription[$i][2]
          . " END\n";
        print TRANSLATION ' '
          . $current_error_number
          . '_prio_'
          . $project . '='
          . $ErrorDescription[$i][4]
          . " END\n";
        print TRANSLATION ' '
          . $current_error_number
          . '_head_'
          . $project . '='
          . $ErrorDescription[$i][5]
          . " END\n";
        print TRANSLATION ' '
          . $current_error_number
          . '_desc_'
          . $project . '='
          . $ErrorDescription[$i][6]
          . " END\n";
        if ( $Template[$i] =~ /[a-zA-z0-0]/ ) {
            print TRANSLATION ' '
              . $current_error_number
              . '_templates_'
              . $project . '='
              . $Template[$i]
              . " END\n";
        }
        print TRANSLATION "\n";
        print TRANSLATION
'###########################################################################'
          . "\n";
        print TRANSLATION "\n";
    }

    print TRANSLATION '</pre>' . "\n";
    close TRANSLATION;

    return ();
}

###########################################################################
## REPLACE SPECIAL LETTERS
###########################################################################

sub replace_special_letters {
    my ($content) = @_;

    $content =~ s/&lt;/</g;
    $content =~ s/&gt;/>/g;
    $content =~ s/&quot;/"/g;
    $content =~ s/&#039;/'/g;
    $content =~ s/&amp;/&/g;

    return ($content);
}

##########################################################################
## TWO COLUMN DISPLAY
##########################################################################

sub two_column_display {
    my ( $text1, $text2 ) = @_;

    printf "%-30s %-30s\n", $text1, $text2;

    return ();
}

##########################################################################
## RAW TEXT
##########################################################################

sub raw_text {
    my ($title) = @_;
    my $servername = $project;

    $title =~ s/&amp;/%26/g;    # Problem with & in title
    $title =~ s/&#039;/'/g;     # Problem with apostroph in title
    $title =~ s/&lt;/</g;
    $title =~ s/&gt;/>/g;
    $title =~ s/&quot;/"/g;
    if (
        !(
               $servername =~ s/^nds_nlwiki$/nds-nl.wikipedia.org/
            || $servername =~ s/^([a-z]+)wiki$/$1.wikipedia.org/
            || $servername =~ s/^([a-z]+)wikisource$/$1.wikisource.org/
            || $servername =~ s/^([a-z]+)wikiversity$/$1.wikiversity.org/
            || $servername =~ s/^([a-z]+)wiktionary$/$1.wiktionary.org/
            || $servername =~ s/^([a-z]+)wikivoyage$/$1.wikivoyage.org/
        )
      )
    {
        die( "Couldn't calculate server name for project" . $project . "\n" );
    }

    my $url = $servername;

    $url =
        'http://'
      . $servername
      . '/w/api.php?action=query&prop=revisions&titles='
      . $title
      . '&rvslots=main&rvprop=timestamp|content&format=xml';

    my $response2;
    uri_escape_utf8($url);

    my $ua2 = LWP::UserAgent->new;
    $response2 = $ua2->get($url);

    my $content2 = $response2->content;
    my $result2  = q{};
    if ($content2) {
        $result2 = $content2;
    }

    $result2 = decode( 'utf-8', $result2 );

    return ($result2);
}
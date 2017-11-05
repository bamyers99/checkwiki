#! /usr/bin/env perl

###########################################################################
##
## FILE:   update_html.pl
## USAGE:  update_html.pl --database <databasename> --host <host>
##                        --password <password> --user <username>
##                        --project <project> (optional)
##
## DESCRIPTION:  Updates all html files of Checkwiki.  These include the
##               top level index.html and pages for each project (this
##               includes index.html, priority_high, priority_middle.html
#                priority_all.html and priority_low.html
##               Program should run just after update_db.pl
##
## AUTHOR:  Stefan Kühn, Bryan White
## VERSION: 2015-07-30
## LICENSE: GPLv3
##
###########################################################################

use strict;
use warnings;

use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);
use utf8;

binmode( STDOUT, ":encoding(UTF-8)" );

our $output_directory  = '/data/project/checkwiki/public_html';
our $webpage_directory = 'https://tools.wmflabs.org/checkwiki';
our $script_name = 'cgi-bin/checkwiki.cgi';

our $dbh;
our @project;

my ( $DbName, $DbServer, $DbUsername, $DbPassword );
my $ProjectName = q{};

my @Options = (
    'database=s' => \$DbName,
    'host=s'     => \$DbServer,
    'password=s' => \$DbPassword,
    'user=s'     => \$DbUsername,
    'project=s'  => \$ProjectName
);

GetOptions(
    'c=s' => sub {
        my $f = IO::File->new( $_[1], '<:encoding(UTF-8)' )
          or die( "Can't open " . $_[1] . "\n" );
        local ($/);
        my $s = <$f>;
        $f->close();
        my ( $Success, $RemainingArgs ) = GetOptionsFromString( $s, @Options );
        die unless ( $Success && !@$RemainingArgs );
    },
    @Options
);

##########################################################################
## MAIN PROGRAM
##########################################################################

our $time = gmtime();

open_db();
build_start_page();
#get_all_projects();
#build_project_page();
#build_prio_page();
close_db();

print 'Finish' . "\n";

###########################################################################
### OPEN DATABASE
###########################################################################

sub open_db {

    # Database configuration.
    #my $DbName = 'p50380g50450__checkwiki_p';
    #my $DbServer;
    #my $DbUsername = 'p50380g50450';
    #my $DbPassword = 'zahgetumataefeex';

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : '' ),
        $DbUsername,
        $DbPassword,
        {
            RaiseError => 1,
            AutoCommit => 1,
            mysql_enable_utf8 => 1
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
## BUILD START PAGE
###########################################################################

sub build_start_page {
    print 'Build Startpage' . "\n";
    my $result = q{};
    $result .= html_head_start();
    $result .= '<title>Check Wikipedia</title>' . "\n";
    $result .=
      '<link rel="stylesheet" href="css/style.css" type="text/css" />' . "\n";
    $result .= html_head_end();
    $result .= '<p>Homepage</p>' . "\n";
    $result .= '<p>' . "\n";
    $result .= '<ul>' . "\n";
    $result .=
'<li>More information at the <a href="https://en.wikipedia.org/wiki/Wikipedia:WikiProject_Check_Wikipedia">projectpage</a></li>'
      . "\n";
    $result .= '</ul>' . "\n";

    $result .=
'<p>Choose your project! - <small>This table will updated every 30 minutes. Last update: '
      . $time
      . ' (UTC)</small></p>' . "\n";
    $result .= get_projects();

    $result .= html_end();

    my $filename = $output_directory . q{/} . 'index.html';

    #print 'Output in:'."\t".$filename."\n";

    open( my $file, ">:encoding(UTF-8)", $filename ) or die "unable to open: $!\n";
    print $file $result;
    close($file);

    return ();
}

###########################################################################
## GET PROJECT
###########################################################################

sub get_projects {

    # List all projects at homepage

    my $result = q{};
    $result .= '<table class="table">';
    $result .= '<tr>' . "\n";
    $result .= '<th class="table">#</th>' . "\n";
    $result .= '<th class="table">Project</th>' . "\n";
    $result .= '<th class="table">To-do</th>' . "\n";
    $result .= '<th class="table">Done</th>' . "\n";
    $result .= '<th class="table">Change to<br />yesterday</th>' . "\n";
    $result .= '<th class="table">Change to<br />last week</th>' . "\n";
    $result .= '<th class="table">Last dump</th>' . "\n";
    $result .= '<th class="table">Last update</th>' . "\n";
    $result .= '<th class="table">Page at Wikipedia</th>' . "\n";
    $result .= '<th class="table">Translation</th>' . "\n";
    $result .= '</tr>' . "\n";

    my $sth = $dbh->prepare(
'SELECT id, project, errors, done, lang, project_page, translation_page, last_update, date(last_dump) from cw_overview ORDER BY project;'
    ) || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        foreach (@$arrayref) {
            $output[$i] = $_;
            $output[$i] = q{} unless defined $output[$i];
            $i++;
        }

        # PRINT OUT "PROJECT NUMBER" and "PROJECT" COLUMNS
        $result .= '<tr>' . "\n";
        $result .= '<td class="table">' . $output[0] . '</td>' . "\n";
        $result .=
          '<td class="table"><a href="'
          . $script_name
          . '?project='
          . $output[1]
          . '&amp;view=project">'
          . $output[1]
          . '</a></td>' . "\n";

        # PRINT OUT "TO-DO" and "DONE" COLUMNS
        $result .=
          '<td class="table" style="text-align:right;">'
          . $output[2] . '</td>' . "\n";
        $result .=
          '<td class="table" style="text-align:right;">'
          . $output[3] . '</td>' . "\n";

        # PRINT OUT "CHANGE TO YESTERDAY" and "CHANGE TO LAST WEEK" COLUMN

#$result .= '<td class="table" style="text-align:right; vertical-align:middle;">'
#  . $output[9] . '</td>' . "\n";
#$result .= '<td class="table" style="text-align:right; vertical-align:middle;">'
#  . $output[10] . '</td>' . "\n";
        $result .=
          '<td class="table" style="text-align:right;">'
          . ' </td>' . "\n";
        $result .=
          '<td class="table" style="text-align:right;">'
          . ' </td>' . "\n";

        # PRINT OUT "LAST DUMP" AND "LAST UPDATE" COLUMNS
        $result .=
          '<td class="table" style="text-align:right;">'
          . $output[8] . '</td>' . "\n";
        $result .= '<td class="table style="text-align:right;">'
          . time_string( $output[7] ) . '</td>' . "\n";

        # PRINT OUT "PAGE AT WIKIPEDIA" AND "TRANSLATION" COLUMNS
        $output[5] =~ tr/ /_/;
        $result .=
'<td class="table" style="text-align:center;"><a href="https://'
          . $output[4]
          . '.wikipedia.org/wiki/'
          . $output[5]
          . '">here</a></td>' . "\n";

        $output[6] =~ tr/ /_/;
        $result .=
'<td class="table" style="text-align:center;"><a href="https://'
          . $output[4]
          . '.wikipedia.org/wiki/'
          . $output[6]
          . '">here</a></td>' . "\n";
        $result .= '</tr>' . "\n";

    }
    $result .= '</table>' . "\n\n";

    return ($result);
}

###########################################################################
## GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
###########################################################################

sub get_all_projects {

    my $sth = $dbh->prepare('SELECT project FROM cw_overview ORDER BY project;')
      || die "Problem with statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my $result = q{};
    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        foreach (@$arrayref) {
            push( @project, $_ );
        }
    }

    if ( $ProjectName ne 'all' ) {
        @project = $ProjectName;
    }

    return ();
}

###########################################################################
## BUILD INDIVIDUAL PROJECT'S HTML PAGE
###########################################################################

sub build_project_page {
    print 'Build project page' . "\n";
    foreach (@project) {

        my $project = $_;

        # CREATE SUBDIRECTORY IF IT DOES NOT EXIST
        if ( not( -e $output_directory . q{/} . $project ) ) {
            print 'create directory: '
              . $output_directory . q{/}
              . $project . "\n";
            mkdir( $output_directory . q{/} . $project, 0777 );
        }

        # CREATE INDEX.HTML FOR EACH PROJECT

        my $result = q{};
        $result .= html_head_start();
        $result .= '<title>Check Wikipedia - ' . $project . '</title>' . "\n";
        $result .=
            '<link rel="stylesheet" href="../css/style.css" type="text/css" />'
          . "\n";
        $result .= html_head_end();
        $result .= '<p><a href="../index.htm">Homepage</a> → '
          . $project . '</p>' . "\n";

        my $sql_text =
"SELECT lang, project_page, translation_page, last_update FROM cw_overview WHERE project = '"
          . $project . "'; ";

        my $sth = $dbh->prepare($sql_text)
          || die "Problem with statement: $DBI::errstr\n";
        $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

        my $project_page     = q{};
        my $translation_page = q{};
        my $lang             = q{};
        my @output;
        while ( my $arrayref = $sth->fetchrow_arrayref() ) {
            my $i = 0;
            foreach (@$arrayref) {
                $output[$i] = $_;
                $output[$i] = q{} unless defined $output[$i];
                $i++;
            }
        }

        $lang             = $output[0];
        $project_page     = $output[1];
        my $temp_page     = $output[1];
        $temp_page        =~ tr/ /_/;
        $translation_page = $output[2];
        my $temp1_page    = $output[2];
        $temp1_page       =~ tr/ /_/;

        $result .= '<p>' . "\n";
        $result .= '<ul>' . "\n";
        $result .=
            '<li>local page: <a href="https://'
          . $lang
          . '.wikipedia.org/wiki/'
          . $temp_page
          . '" target="_blank">'
          . $project_page
          . '</a></li>' . "\n";
        $result .= '<li>page for translation: ';
        $result .=
            '<a href="https://'
          . $lang
          . '.wikipedia.org/wiki/'
          . $temp1_page
          . '" target="_blank">here</a>'
          if ( $translation_page ne '' );
        $result .= 'unknown!' if ( $translation_page eq '' );
        $result .= '</li>' . "\n" . '</ul>' . "\n";

        $result .=
            '<p><small>This table will updated every 30 minutes. Last update: '
          . $time 
          . ' (UTC)</small></p>' . "\n";

        $result .= '<table class="table">';
        $result .=
'<tr><th class="table">&nbsp;</th><th class="table">To-do</th><th class="table">Done</th></tr>'
          . "\n";
        $result .= get_number_of_prio($project);
        $result .= '</table>';

        $result .= html_end();
        my $filename = $output_directory . '/' . $project . '/' . 'index.htm';

        open( my $file, ">:encoding(UTF-8)", $filename ) or die "unable to open: $!\n";
        print $file $result;
        close($file);

    }

    return ();
}

###########################################################################
## GET NUMBER OF PROBLEMS IN ARTICLES
###########################################################################

sub get_number_of_prio {
    my ($param_project) = @_;
    my $script_name = 'checkwiki.cgi';

    my $sql_text =
"SELECT IFNULL(sum(errors),0), prio, IFNULL(sum(done),0) FROM cw_overview_errors WHERE project = '"
      . $param_project
      . "' group by prio having prio > 0 order by prio;";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my $result        = q{};
    my $sum_of_all    = 0;
    my $sum_of_all_ok = 0;

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        foreach (@$arrayref) {
            $output[$i] = $_;
            $output[$i] = q{} unless defined $output[$i];
            $i++;
        }

        my $number_of_error = $i;
        $result .= '<tr><td class="table" style="text-align:right;"><a href=';
        $result .= '"priority_high.htm"   rel="nofollow">high priority'
          if ( $output[1] == 1 );
        $result .= '"priority_middle.htm" rel="nofollow">middle priority'
          if ( $output[1] == 2 );
        $result .= '"priority_low.htm"    rel="nofollow">low priority'
          if ( $output[1] == 3 );
        $result .=
'</a></td><td class="table" style="text-align:right; vertical-align:middle;">'
          . $output[0]
          . '</td><td class="table" style="text-align:right; vertical-align:middle;">'
          . $output[2]
          . '</td></tr>' . "\n";
        $sum_of_all    = $sum_of_all + $output[0];
        $sum_of_all_ok = $sum_of_all_ok + $output[2];

        if ( $output[1] == 3 ) {

            # sum -> all priorities
            my $result2 = q{};
            $result2 .=
'<tr><td class="table" style="text-align:right;"><a href="priority_all.htm">all priorities';
            $result2 .=
'</a></td><td class="table"  style="text-align:right; vertical-align:middle;">'
              . $sum_of_all
              . '</td><td class="table"  style="text-align:right; vertical-align:middle;">'
              . $sum_of_all_ok
              . '</td></tr>' . "\n";

            $result = $result2 . $result;
        }

    }
    return ($result);
}

###########################################################################
## CALL TO BUILD INDIVIDUAL PROJECT'S HTML PAGES
###########################################################################

sub build_prio_page {
    print 'Build Priority page' . "\n";
    foreach (@project) {

        #print $_."\n";
        my $project = $_;

        build_prio_page2( $project, 'high' );
        build_prio_page2( $project, 'middle' );
        build_prio_page2( $project, 'low' );
        build_prio_page2( $project, 'all' );
    }

    return ();
}

###########################################################################
## BUILD INDIVIDUAL PROJECT'S HTML PAGES
###########################################################################

sub build_prio_page2 {
    my ( $project, $param_view ) = @_;
    my $prio      = 0;
    my $headline  = q{};
    my $file_name = q{};

    if ( $param_view eq 'high' ) {
        $prio      = 1;
        $headline  = 'High priority';
        $file_name = 'priority_high.htm';
    }

    if ( $param_view eq 'middle' ) {
        $prio      = 2;
        $headline  = 'Middle priority';
        $file_name = 'priority_middle.htm';
    }

    if ( $param_view eq 'low' ) {
        $prio      = 3;
        $headline  = 'Low priority';
        $file_name = 'priority_low.htm';
    }

    if ( $param_view eq 'all' ) {
        $prio      = 0;
        $headline  = 'All priorities';
        $file_name = 'priority_all.htm';
    }

    my $result = q{};
    $result .= html_head_start();
    $result .= '<title>Check Wikipedia - ' . $project . '</title>' . "\n";
    $result .=
        '<link rel="stylesheet" href="../css/style.css" type="text/css" />'
      . "\n";
    $result .= html_head_end();
    $result .= '<p><a href="../index.htm">Homepage</a> → ';
    $result .= '<a href="index.htm">' . $project . '</a> → ';
    $result .= $headline . '</p>' . "\n";

    $result .=
'<p>Priorities: <a href="priority_all.htm">all</a> - <a href="priority_high.htm">high</a> - <a href="priority_middle.htm">middle</a> - <a href="priority_low.htm">low</a></p>'
      . "\n";
    $result .=
      '<p><small>This table will updated every 30 minutes.<br> Last update: '
          . $time . ' (UTC)</small></p>' . "\n";

    $result .= get_number_error_and_desc_by_prio( $project, $prio );
    $result .= html_end();

    my $filename = $output_directory . '/' . $project . '/' . $file_name;

    open( my $file, ">:encoding(UTF-8)", $filename ) or die "unable to open: $!\n";
    print $file $result;
    close($file);

    return ();
}

###########################################################################

sub get_number_error_and_desc_by_prio {
    my ( $param_project, $prio ) = @_;
    my $sql_text =
"SELECT IFNULL(errors, '') todo, IFNULL(done, '') ok, name, name_trans, id, prio FROM cw_overview_errors WHERE prio = "
      . $prio
      . " AND project = '"
      . $param_project
      . "' ORDER BY name_trans, name;";

    if ( $prio == 0 ) {

        # SHOW ALL PRIORITIES FOR AN INDIVIDUAL PROJECT
        $sql_text =
"SELECT IFNULL(errors, '') todo, IFNULL(done, '') ok, name, name_trans, id, prio FROM cw_overview_errors WHERE project = '"
          . $param_project
          . "' order by name_trans, name;";
    }

    if ( $prio == 0 and $param_project eq 'all' ) {

        # SHOW ALL PRIORITIES FOR ALL PROJECTS
        $sql_text =
"SELECT IFNULL(errors, '') todo, IFNULL(done, '') ok, name, name_trans, id, prio FROM cw_overview_errors ORDER BY name_trans, name;";
    }

    my $result = q{};
    $result .= '<table class="table">';
    $result .= '<tr>';
    $result .= '<th class="table">Priority</th>';
    $result .= '<th class="table">To-do</th>';
    $result .= '<th class="table">Done</th>';
    $result .= '<th class="table">Description</th>';
    $result .= '<th class="table">ID</th>';
    $result .= '</tr>' . "\n";

    my $sth = $dbh->prepare($sql_text)
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    while ( my $arrayref = $sth->fetchrow_arrayref() ) {
        my @output;
        my $i = 0;
        foreach (@$arrayref) {
            $output[$i] = $_;
            $output[$i] = q{} unless defined $output[$i];
            $i++;
        }

        my $headline = $output[2];
        $headline = $output[3] if ( $output[3] ne q{} );

        $result .= '<tr>';
        $result .=
          '<td class="table" style="text-align:right; vertical-align:middle;">'
          . priority_marker( $output[5] ) . '</td>';
        $result .=
          '<td class="table" style="text-align:right; vertical-align:middle;">'
          . $output[0] . '</td>';
        $result .=
          '<td class="table" style="text-align:right; vertical-align:middle;">'
          . $output[1] . '</td>';
        $result .=
'<td class="table"><a href="https://tools.wmflabs.org/checkwiki/cgi-bin/checkwiki.cgi?project='
          . $param_project
          . '&amp;view=only&amp;id='
          . $output[4]
          . '" rel="nofollow">'
          . $headline
          . '</a></td>';
        $result .=
          '<td class="table" style="text-align:right; vertical-align:middle;">'
          . $output[4] . '</td>';
        $result .= '</tr>' . "\n";

    }
    $result .= '</table>';
    return ($result);
}

###########################################################################

sub priority_marker {
    my ($prio) = @_;
    my $result = q{};

    $result = ' deactivated' if ( $prio < 1 or $prio > 3 );
    $result = ' high' if ( $prio == 1 ); #<span style="color:#8A0808">❶</span>
    $result = ' middle'
      if ( $prio == 2 );                 #<span style="color:#FF0000">❷</span>
    $result = ' low' if ( $prio == 3 ); # <span style="color:#FF8000">❸</span>

    return ($result);
}

###########################################################################

sub time_string {
    my ($timestring) = @_;
    my $result = q{};
    if ( $timestring ne q{} ) {
        $result = $timestring . '---';
        $result = $timestring;
        $result =~ s/ /&nbsp;/g;

    }
    return ($result);
}

###########################################################################
sub html_head_start {
    my $result = "<!DOCTYPE html>\n<head>\n<meta charset=\"UTF-8\" />\n";

    return ($result);
}

sub html_head_end {
    my $result = "</head>\n<body>\n<h1>Check Wikipedia</h1>\n";

    return ($result);
}

sub html_end {
    my $result = q{};
    $result .= '<p><span style="font-size:10px;">' . "\n";
    $result .=
'<a href="https://en.wikipedia.org/wiki/Wikipedia:WikiProject_Check_Wikipedia">projectpage</a> · '
      . "\n";
    $result .=
'<a href="https://en.wikipedia.org/wiki/Wikipedia_talk:WikiProject_Check_Wikipedia">comments and bugs</a><br />'
      . "\n";
    $result .= 'Version 2015-07-30 · ' . "\n";
    $result .=
        'license: <a href="http://www.gnu.org/copyleft/gpl.html">GPLv3</a> · '
      . "\n";
    $result .=
'Powered by <a href="https://www.mediawiki.org/wiki/Wikimedia_Labs">Wikimedia Labs</a> '
      . "\n";
    $result .= '</span></p>' . "\n";

    $result .= '</body>' . "\n";
    $result .= '</html>' . "\n";
    return ($result);
}
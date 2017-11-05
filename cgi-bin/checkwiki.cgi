#! /usr/bin/env perl

###########################################################################
#
# FILE:   checkwiki.cgi
# USAGE:
#
# DESCRIPTION:
#
# AUTHOR:  Stefan Kühn, Bryan White
# VERSION: 2017-01-10
# LICENSE: GPLv3
#
###########################################################################

use strict;
use warnings;
use utf8;
use lib
'/data/project/checkwiki/perl5/perlbrew/perls/perl-5.24.0/lib/site_perl/5.24.0/';

use CGI::Lite;
use CGI::Carp qw(fatalsToBrowser);
use DBI;

binmode( STDOUT, ':encoding(UTF-8)' );

our $VERSION     = '2017-01-10';
my  $script_name = 'checkwiki.cgi';

###########################################################################
## GET PARAMETERS FROM CGI
###########################################################################

my $cgi  = CGI::Lite->new();
my $data = $cgi->parse_form_data;

my $param_view    = $data->{view};     # list, high, middle, low, only, detail
my $param_project = $data->{project};
my $param_id      = $data->{id};
my $param_title   = $data->{title};
my $param_offset  = $data->{offset};
my $param_limit   = $data->{limit};
my $param_orderby = $data->{orderby};
my $param_sort    = $data->{sort};

$param_view    = q{} if ( !defined $param_view );
$param_project = q{} if ( !defined $param_project );
$param_id      = q{} if ( !defined $param_id );
$param_title   = q{} if ( !defined $param_title );
$param_offset  = q{} if ( !defined $param_offset );
$param_limit   = q{} if ( !defined $param_limit );
$param_orderby = q{} if ( !defined $param_orderby );
$param_sort    = q{} if ( !defined $param_sort );

$param_view =~ s/[^a-z0-9]/_/g;
$param_project =~ s/[^a-z]/_/g;
$param_title =~ s/[#<>\[\]\|\{\}_\n\r\t]/_/g;

if ( $param_id ne q{} ) {
    $param_id = 1 if ( $param_id !~ /^[+-]?\d+$/ );
}

#############  Offset

if ( $param_offset !~ /^[0-9]+$/ ) {
    $param_offset = 0;
}

#############  Limit

if ( $param_limit !~ /^[0-9]+$/ ) {
    $param_limit = 25;
}
if ( $param_limit > 500 and $param_view ne 'bots' ) {
    $param_limit = 500;
}
if ( $param_view eq 'bots' ) {
    $param_limit = 115_000;
}

#############  Offset

my $offset_lower  = $param_offset - $param_limit;
my $offset_higher = $param_offset + $param_limit;
$offset_lower = 0 if ( $offset_lower < 0 );
my $offset_end = $param_offset + $param_limit;

#############  Sorting
my $column_orderby = q{};
my $column_sort    = q{};

if ( $param_orderby ne q{} ) {
    if (    $param_orderby ne 'article'
        and $param_orderby ne 'notice'
        and $param_orderby ne 'id'
        and $param_orderby ne 'description'
        and $param_orderby ne 'priority'
        and $param_orderby ne 'found'
        and $param_orderby ne 'project'
        and $param_orderby ne 'done'
        and $param_orderby ne 'errors'
        and $param_orderby ne 'last_dump'
        and $param_orderby ne 'last_update'
        and $param_orderby ne 'more' )
    {
        $param_orderby = 'article';
    }
}

if ( $param_sort eq 'desc' ) {
    $column_sort = 'DESC';
}
else {
    $column_sort = 'ASC';
}
##########################################################################
## MAIN PROGRAM
##########################################################################

my $lang;
my $lang_dir = "\n\n" . '<table class="table">';
my $bidi = 0;

if ( $param_project eq q{} ) {
    $lang = 'en';
}
else {
    $lang = substr ( $param_project, 0, 2 );
    $lang = 'en' if ( $param_project eq 'simplewiki' );
    if ( $param_project =~ /arwiki|arcwiki|fawiki|hewiki|yiwiki|urwiki/ ) {
        $lang_dir = "\n\n" . '<table class="table" dir="rtl">';
        $bidi = 1;
    }
}

begin_html();
check_if_no_params();

##########################################################################
## ONLY PROJECT PARAM ENTERED - SHOW PAGE FOR ONLY ONE PROJECT
##########################################################################

if (    $param_project ne q{}
    and $param_view eq 'project'
    and $param_id eq q{}
    and $param_title eq q{} )
{
    print '<p><a href="'
      . $script_name
      . '">Homepage</a> → '
      . $param_project . '</p>' . "\n";

    print project_info($param_project);

    print
'<p><span style="font-size:10px;">This table will update every 15 minutes.</span></p>'
      . "\n";
    print '<table class="table">';
    print
'<tr><th class="table">&nbsp;</th><th class="table">To-do</th><th class="table">Done</th></tr>'
      . "\n\n";
    print get_number_of_prio();
    print '</table>' . "\n\n";

}

##########################################################################
## SHOW ALL ERRORS FOR ONE OR ALL PROJECTS
##########################################################################

if (
    $param_project ne q{}
    and (  $param_view eq 'high'
        or $param_view eq 'middle'
        or $param_view eq 'low'
        or $param_view eq 'all' )
  )
{

    my $prio     = 0;
    my $headline = q{};
    if ( $param_view eq 'high' ) {
        $prio     = 1;
        $headline = 'High priority';
    }

    if ( $param_view eq 'middle' ) {
        $prio     = 2;
        $headline = 'Middle priority';
    }

    if ( $param_view eq 'low' ) {
        $prio     = 3;
        $headline = 'Low priority';
    }

    if ( $param_view eq 'all' ) {
        $prio     = 0;
        $headline = 'all priorities';
    }

    print '<p><a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → '
      . $headline . '</p>' . "\n";

    print '<p>Priorities: <a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=all">all</a> - '
      . '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=high">high</a> - '
      . '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=middle">middle</a> - '
      . '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=low">low</a></p>';

    print
'<p><span style="font-size:10px;">This table will update every 15 minutes.</span></p>'
      . "\n";

    print get_number_error_and_desc_by_prio($prio);

}

##########################################################################
## SET AN ARTICLE AS HAVING AN ERROR DONE
##########################################################################

if (    $param_project ne q{}
    and $param_view =~ /^(detail|only)$/
    and $param_title =~ /^(.)+$/
    and $param_id =~ /^[0-9]+$/ )
{

    my $dbh = connect_database();
    my $sth = $dbh->prepare('UPDATE cw_error SET ok=1 WHERE Title=? AND error=? AND project=?')
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $param_title, $param_id, $param_project )
      or die "Cannot execute: $sth->errstr\n";
}

###########################################################################
## SHOW ONE ERROR FOR ALL ARTICLES
###########################################################################

if (    $param_project ne q{}
    and $param_view =~ /^only(done)?$/
    and $param_id =~ /^[0-9]+$/ )
{

    my $headline = q{};
    $headline = get_headline($param_id);

    my $prio = get_prio_of_error($param_id);

    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=high">high priority</a>'
      if ( $prio eq '1' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=middle">middle priority</a>'
      if ( $prio eq '2' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=low">low priority</a>'
      if ( $prio eq '3' );

    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → '
      . $prio . ' → '
      . $headline . '</p>' . "\n";

    print get_description($param_id) . "\n";
    print '<p>To do: <b>' . get_number_of_error($param_id) . '</b>, ';
    print 'Done: <b>'
      . get_number_of_ok_of_error($param_id)
      . '</b> article(s) - ';
    print 'ID: ' . $param_id . ' - ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=bots&amp;id='
      . $param_id
      . '&amp;offset='
      . $offset_lower
      . '">List for bots</a> - ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=alldone&amp;id='
      . $param_id
      . '">Set all articles as done!</a>';
    print '</p>' . "\n";

###########################################################################
## SHOW ONLY ONE ERROR WITH ALL ARTICLES
###########################################################################

    if ( $param_view eq 'only' ) {
        print '<p><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=onlydone&amp;id='
          . $param_id
          . '">Show all done articles</a></p>';
        print get_article_of_error($param_id);
    }

###########################################################################
## SHOW ONLY ONE ERROR WITH ALL ARTICLES SET AS DONE
###########################################################################

    if ( $param_view eq 'onlydone' ) {
        print '<p><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=only&amp;id='
          . $param_id
          . '">Show to-do-list</a></p>';
        print get_done_article_of_error($param_id);
    }

}

###########################################################################
## SHOW ONE ERROR WITH ALL ARTICLES FOR BOTS
###########################################################################

if (    $param_project ne q{}
    and $param_view eq 'bots'
    and $param_id =~ /^[0-9]+$/ )
{

    print get_article_of_error_for_bots($param_id);
}

################################################################

if (    $param_project ne q{}
    and $param_view eq 'alldone'
    and $param_id =~ /^[0-9]+$/ )
{
    # All article of an error set ok = 1
    my $headline = q{};
    $headline = get_headline($param_id);

    #print '<h2>'.$param_project.' - '.$headline.'</h2>'."\n";
    my $prio = get_prio_of_error($param_id);

    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=high">high priority</a>'
      if ( $prio eq '1' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=middle">middle priority</a>'
      if ( $prio eq '2' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=low">low priority</a>'
      if ( $prio eq '3' );

    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → '
      . $prio . ' → '
      . $headline . '</p>' . "\n";

    print
'<p>You work with a bot or a tool like "AWB" or "WikiCleaner".</p><p>And now you want set all <b>'
      . get_number_of_error($param_id)
      . '</b> article(s) of id <b>'
      . $param_id
      . '</b> as <b>done</b>.</p>';

    print '<ul>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I will back!</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I want only try this link!</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I am not sure. I will go back.</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=alldone2&amp;id='
      . $param_id
      . '">Yes, I will set all <b>'
      . get_number_of_error($param_id)
      . '</b> article(s) as done.</a></li>' . "\n";
    print '</ul>' . "\n";
    print q{};
}

################################################################

if (    $param_project ne q{}
    and $param_view eq 'alldone2'
    and $param_id =~ /^[0-9]+$/ )
{
    # All article of an error set ok = 1
    my $headline = q{};
    $headline = get_headline($param_id);

    #print '<h2>'.$param_project.' - '.$headline.'</h2>'."\n";
    my $prio = get_prio_of_error($param_id);

    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=high">high priority</a>'
      if ( $prio eq '1' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=middle">middle priority</a>'
      if ( $prio eq '2' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=low">low priority</a>'
      if ( $prio eq '3' );

    print '<p> <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → '
      . $prio . ' → '
      . $headline . '</p>' . "\n";

    print
'<p>You work with a bot or a tool like "AWB" or "WikiCleaner".</p><p>And now you want set all <b>'
      . get_number_of_error($param_id)
      . '</b> article(s) of id <b>'
      . $param_id
      . '</b> as <b>done</b>.</p>';

    print
'<p>If you set all articles as done, then only in the database the article will set as done. With the next scan all this articles will be scanned again. If the script found this idea for improvment again, then this article is again in this list.</p>';

    print
'<p>If you want stop this listing, then this is not the way. Please contact the author at the <a href="https://en.wikipedia.org/wiki/Wikipedia_talk:WikiProject_Check_Wikipedia">projectpage</a> and discuss the problem there.</p>';

    print '<ul>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I will back!</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I want only try this link!</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '">No, I am not sure. I will go back.</a></li>' . "\n";
    print '<li><a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=alldone3&amp;id='
      . $param_id
      . '">Yes, I will set all <b>'
      . get_number_of_error($param_id)
      . '</b> article(s) as done.</a></li>' . "\n";
    print '</ul>' . "\n";
    print q{};
}

################################################################

if (    $param_project ne q{}
    and $param_view eq 'alldone3'
    and $param_id =~ /^[0-9]+$/ )
{
    # All article of an error set ok = 1
    my $headline = get_headline($param_id);

    #print '<h2>'.$param_project.' - '.$headline.'</h2>'."\n";
    my $prio = get_prio_of_error($param_id);

    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=high">high priority</a>'
      if ( $prio eq '1' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=middle">middle priority</a>'
      if ( $prio eq '2' );
    $prio =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=low">low priority</a>'
      if ( $prio eq '3' );

    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → '
      . $prio . ' → '
      . $headline . '</p>' . "\n";

    print '<p>All <b>'
      . get_number_of_error($param_id)
      . '</b> article(s) of id <b>'
      . $param_id
      . '</b> were set as <b>done</b></p>';

    my $dbh = connect_database();

    my $sth =
      $dbh->prepare('UPDATE cw_error SET ok=1 WHERE error= ? AND project= ?;')
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $param_id, $param_project )
      or die "Cannot execute: $sth->errstr\n";

    print 'Back to ' . $prio . "\n";
}

################################################################

if (    $param_project ne q{}
    and $param_view eq 'detail'
    and $param_title =~ /^(.)+$/ )
{
    
    print '<p>→ <a href="' . $script_name . '">Homepage</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=project">'
      . $param_project
      . '</a> → ';
    print '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=list">List</a> → Details</p>' . "\n";

    my $homepage = get_homepage($param_project);
    my $dbh      = connect_database();

    my $sth = $dbh->prepare(
        'SELECT title FROM cw_error WHERE Title= ? AND project= ? limit 1;')
      or die "Problem with statement: $DBI::errstr\n";
    $sth->execute( $param_title, $param_project )
      or die "Cannot execute: $sth->errstr\n";

    my $title_sql;
    $sth->bind_col( 1, \$title_sql );

    while ( $sth->fetchrow_arrayref() ) {
        my $title_under = $title_sql;
        $title_under =~ tr/ /_/;

        print '<p>Article: <a href=https://'
          . $homepage
          . '/wiki/'
          . $title_under . '>'
          . $title_sql
          . '</a> - <a href="https://'
          . $homepage
          . '/w/index.php?title='
          . $title_under
          . '&amp;action=edit">edit</a></p>';
    }

    print get_all_error_of_article($param_title);

}

##############################################################
if ( $param_view ne 'bots' ) {

    my $result2;
    $result2 = '<p><span style="font-size:10px;">' . "\n";
    $result2 .=
'<a href="https://en.wikipedia.org/wiki/Wikipedia:WikiProject_Check_Wikipedia">projectpage</a> · '
      . "\n";
    $result2 .=
'<a href="https://en.wikipedia.org/wiki/Wikipedia_talk:WikiProject_Check_Wikipedia">comments and bugs</a><br />'
      . "\n";
    $result2 .= 'Version ' . $VERSION . ' · ' . "\n";
    $result2 .=
        'license: <a href="https://www.gnu.org/copyleft/gpl.html">GPLv3</a> · '
      . "\n";
    $result2 .=
'Powered by <a href="https://www.mediawiki.org/wiki/Wikimedia_Labs">Wikimedia Labs</a> '
      . "\n";
    $result2 .= '</span></p>' . "\n";

    print $result2;
}

# AWB needs this
print '</body>' . "\n";
print '</html>' . "\n";

####################################################################################################################
####################################################################################################################
####################################################################################################################
####################################################################################################################
####################################################################################################################

##########################################################################
## NO PARAMS ENTERED - SHOW STARTPAGE WITH OVERVIEW OF ALL PROJECTS
##########################################################################

sub check_if_no_params {
    if (    $param_project eq q{}
        and $param_view eq q{}
        and $param_id eq q{}
        and $param_title eq q{} )
    {

        if ( $param_orderby eq q{} ) {
            $column_orderby = 'project';
        }
        else {
            $column_orderby = $param_orderby;
        }

        print '<p>→ Homepage</p>' . "\n";
        print
'<p>More information at the <a href="https://en.wikipedia.org/wiki/Wikipedia:WikiProject_Check_Wikipedia">projectpage</a>.</p>'
          . "\n";
        print '<p>Choose your project!</p>' . "\n";
        print
'<p><span style="font-size:10px;">This table will update every 15 minutes.</span></p>'
          . "\n";
        print get_projects($column_orderby);
    }

    return ();

}

##########################################################################
## BEGIN HTML FOR ALL PAGES
##########################################################################

sub begin_html {

    print "Content-type: text/html\n\n";
    print "<!DOCTYPE html>\n";
    print qq{<html lang="$lang">\n};
    print qq{<head>\n<meta charset=\"UTF-8\" />\n};
    print "<title>Check Wikipedia</title>\n";

    if ( $param_view ne 'bots' ) {
        print '<link rel="stylesheet" href="https://tools.wmflabs.org/checkwiki/css/style.css" type="text/css" />' . "\n";
    }
#    print get_style() if ( $param_view ne 'bots' );
    print "</head>\n";
    print "<body>\n\n";
    print "<h1>Check Wikipedia</h1>\n\n" if ( $param_view ne 'bots' );

    return ();
}

##########################################################################
## GET NUMBER OF ALL ERRORS OVER ALL PROJECTS
##########################################################################

sub get_number_all_errors_over_all {
    my $dbh    = connect_database();
    my $result = 0;

    my $sth = $dbh->prepare('SELECT count(*) FROM cw_error WHERE ok=0;')
      or die "Problem with statement: $DBI::errstr\n";
    $sth->execute
      or die "Cannot execute: $sth->errstr\n";

    $result = $sth->fetchrow();

    return ($result);
}

###########################################################################

sub get_number_of_ok_over_all {
    my $dbh    = connect_database();
    my $result = 0;

    my $sth = $dbh->prepare('SELECT count(*) FROM cw_error WHERE ok=1;')
      or die "Problem with statement: $DBI::errstr\n";
    $sth->execute
      or die "Cannot execute: $sth->errstr\n";

    $result = $sth->fetchrow();

    return ($result);
}

###########################################################################

sub get_projects {
    my ($orderby) = @_;
    my $result    = q{};
    my $dbh       = connect_database();

    $result .= "\n\n" . '<table class="table">' . "\n";
    $result .= '<tr>' . "\n";
    $result .= '<th class="table">Project';
    $result .=
      '<a href="' . $script_name . '?orderby=project&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?orderby=project&amp;sort=desc">↓</a> </th>' . "\n";
    $result .= '<th class="table">To-do';
    $result .=
      '<a href="' . $script_name . '?orderby=errors&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?orderby=errors&amp;sort=desc">↓</a> </th>' . "\n";
    $result .= '<th class="table">Done';
    $result .=
      '<a href="' . $script_name . '?orderby=done&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?orderby=done&amp;sort=desc">↓</a> </th>' . "\n";
    $result .= '<th class="table">Last dump';
    $result .=
      '<a href="' . $script_name . '?orderby=last_dump&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?orderby=last_dump&amp;sort=desc">↓</a> </th>' . "\n";
    $result .= '<th class="table">Last update';
    $result .=
      '<a href="' . $script_name . '?orderby=last_update&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?orderby=last_update&amp;sort=desc">↓</a> </th>' . "\n";
    $result .= '<th class="table">Page at Wikipedia</th>' . "\n";
    $result .= '<th class="table">Translation</th>' . "\n";
    $result .= '</tr>' . "\n";

    my $sth = $dbh->prepare(
'SELECT ID, project, errors, done, lang, project_page, translation_page, last_update, last_dump FROM cw_overview ORDER BY '
          . $orderby . q{ } 
          . $column_sort . q{;} )
        or die "Problem with statement: $DBI::errstr\n";
    $sth->execute
        or die "Cannot execute: $sth->errstr\n";

    my ( $id_sql, $project_sql, $errors_sql, $done_sql, $lang_sql, $page_sql, $trans_sql, $lastdump_sql, $dumpdate_sql);
        $sth->bind_col( 1, \$id_sql );
        $sth->bind_col( 2, \$project_sql );
        $sth->bind_col( 3, \$errors_sql );
        $sth->bind_col( 4, \$done_sql );
        $sth->bind_col( 5, \$lang_sql );
        $sth->bind_col( 6, \$page_sql );
        $sth->bind_col( 7, \$trans_sql );
        $sth->bind_col( 8, \$lastdump_sql );
        $sth->bind_col( 9, \$dumpdate_sql );

    while ( $sth->fetchrow_arrayref ) {

        # PRINT OUT "PROJECT NUMBER" and "PROJECT" COLUMNS
        $result .= '<tr>' . "\n\n";
        $result .=
            '<td class="table"><a href="'
          . $script_name
          . '?project='
          . $project_sql
          . '&amp;view=project">'
          . $project_sql
          . '</a></td>' . "\n";

        # PRINT OUT "TO-DO" and "DONE" COLUMNS
        $result .=
          '<td class="table" style="text-align:right;">'
          . $errors_sql . '</td>' . "\n";
        $result .=
          '<td class="table" style="text-align:right;">'
          . $done_sql . '</td>' . "\n";

        # PRINT OUT "LAST DUMP" AND "LAST UPDATE" COLUMNS
        $result .=
          '<td class="table" style="text-align:center;">'
          . $dumpdate_sql . '</td>' . "\n";
        $result .= '<td class="table" style="text-align:center;">'
          . substr( $lastdump_sql, 0, 10 ) . '</td>' . "\n";

        # PRINT OUT "PAGE AT WIKIPEDIA" AND "TRANSLATION" COLUMNS
        $page_sql =~ tr/ /_/;
        $result .=
            '<td class="table" style="text-align:center;"><a href="https://'
          . $lang_sql
          . '.wikipedia.org/wiki/'
          . $page_sql
          . '">here</a></td>' . "\n";

        $trans_sql =~ tr/ /_/;
        $result .=
            '<td class="table" style="text-align:center;"><a href="https://'
          . $lang_sql
          . '.wikipedia.org/wiki/'
          . $trans_sql
          . '">here</a></td>' . "\n";
        $result .= '</tr>' . "\n";

    }

    $result .= '</table>' . "\n\n";
    return ($result);
}

###########################################################################

sub get_number_all_article {
    my $result = 0;
    my $dbh    = connect_database();

    my $sth = $dbh->prepare(
'SELECT count(a.error_id) FROM (select error_id FROM cw_error WHERE ok=0 AND project= ? GROUP BY error_id) a;' )
        or die "Problem with statement: $DBI::errstr\n";
    $sth->execute($param_project)
        or die "Cannot execute: $sth->errstr \n";

    $result = $sth->fetchrow();

    return ($result);
}

###########################################################################

sub get_number_of_ok {
    my $result = 0;
    my $dbh    = connect_database();

    my $sth = $dbh->prepare(
        'SELECT IFNULL(sum(done),0) FROM cw_overview_errors WHERE project= ?;')
      or die "Problem with statement: $DBI::errstr\n";
    $sth->execute($param_project)
      or die "Cannot execute: $sth->errstr\n";

    $result = $sth->fetchrow();

    return ($result);
}

###########################################################################

sub get_number_all_errors {
    my $result = 0;
    my $dbh    = connect_database();

    my $sth = $dbh->prepare(
      'SELECT IFNULL(sum(errors),0) FROM cw_overview_errors WHERE project= ?;')
      or die "Problem with statement: $DBI::errstr\n";
    $sth->execute($param_project)
      or die "Cannot execute: $sth->errstr\n";

    $result = $sth->fetchrow();

    return ($result);
}

###########################################################################

sub get_number_of_error {
    my ($error) = @_;
    my $result  = 0;
    my $dbh     = connect_database();

    my $sth = $dbh->prepare(
        'SELECT count(*) FROM cw_error WHERE ok=0 AND error= ? AND project= ?;')
      or die "Problem with statement: $DBI::errstr\n";
    $sth->execute( $error, $param_project )
      or die "Cannot execute: $sth->errstr\n";

    $result = $sth->fetchrow();

    if ( !defined($result) ) {
        $result = q{};
    }

    return ($result);
}

###########################################################################

sub get_number_of_ok_of_error {

    my ($error) = @_;
    my $result  = 0;
    my $dbh     = connect_database();

    my $sth = $dbh->prepare(
        'SELECT count(*) FROM cw_error WHERE ok=1 AND error= ? AND project= ?;')
      or die "Problem with statement: $DBI::errstr\n";
    $sth->execute( $error, $param_project )
      or die "Cannot execute: $sth->errstr\n";

    $result = $sth->fetchrow();

    return ($result);
}

###########################################################################
### GET PROJECT INFORMATION FOR PROJECT'S STARTPAGE
############################################################################

sub project_info {
    my ($project) = @_;
    my $result    = q{};
    my $dbh       = connect_database();

    my $sth = $dbh->prepare( q{SELECT project,
    if(length(ifnull(project_page,''))!=0,project_page, 'no data') project_page,
    if(length(ifnull(translation_page,''))!=0,translation_page, 'no data') translation_page,
    date_format(last_dump,'%Y-%m-%d') last_dump, 
    ifnull(DATEDIFF(curdate(),last_dump),'')
    FROM cw_overview WHERE project= ? limit 1;} )
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project)
      or die "Cannot execute: $sth->errstr\n";

    my ( $project_sql,  $wikipage_sql, $translation_sql, $lastdump_sql, $dumpdate_sql);
    $sth->bind_col( 1, \$project_sql );
    $sth->bind_col( 2, \$wikipage_sql );
    $sth->bind_col( 3, \$translation_sql );
    $sth->bind_col( 4, \$lastdump_sql );
    $sth->bind_col( 5, \$dumpdate_sql );

    $sth->fetchrow_arrayref;

    my $homepage              = get_homepage($project_sql);
    my $wikipage_sql_under    = $wikipage_sql;
    my $translation_sql_under = $translation_sql;
    $wikipage_sql_under =~ tr/ /_/;
    $translation_sql_under =~ tr/ /_/;

    $result .= '<ul>' . "\n";
    $result .=
        '<li>Local page: '
      . '<a href="https://'
      . $homepage
      . '/wiki/'
      . $wikipage_sql_under . '">'
      . $wikipage_sql
      . '</a></li>' . "\n";
    $result .=
        '<li>Translation page: '
      . '<a href="https://'
      . $homepage
      . '/wiki/'
      . $translation_sql_under
      . '">here</a></li>' . "\n";
    $result .=
        '<li>Last scanned dump '
      . $lastdump_sql . ' ('
      . $dumpdate_sql
      . ' days old)</li>' . "\n";

    $result .= '</ul>';

    return ($result);
}

#############################################################
# Show priority table (high, medium, low) + Number of errors
#############################################################

sub get_number_of_prio {
    my $result = q{};
    my $dbh    = connect_database();

    my $sth = $dbh->prepare(
'SELECT IFNULL(sum(errors),0), prio, IFNULL(sum(done),0)  FROM cw_overview_errors WHERE project= ? GROUP BY prio HAVING prio > 0 ORDER BY prio;' )
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($param_project)
      or die "Cannot execute: $sth->errstr\n";

    my $sum_of_all    = 0;
    my $sum_of_all_ok = 0;

    my ( $errors_sql, $priority_sql, $done_sql );
    $sth->bind_col( 1, \$errors_sql );
    $sth->bind_col( 2, \$priority_sql );
    $sth->bind_col( 3, \$done_sql );

    while ( $sth->fetchrow_arrayref ) {

        $result .=
            '<tr><td class="table" style="text-align:right;"><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=';
        $result .= 'nothing">deactivated'
          if ( $priority_sql == 0 );
        $result .= 'high">high priority'
          if ( $priority_sql == 1 );
        $result .= 'middle">middle priority'
          if ( $priority_sql == 2 );
        $result .= 'low">low priority'
          if ( $priority_sql == 3 );

        $result .=
            '</a></td><td class="table" style="text-align:right;">'
          . $errors_sql
          . '</td><td class="table" style="text-align:right;">'
          . $done_sql
          . '</td></tr>' . "\n";
        $sum_of_all    = $sum_of_all + $errors_sql;
        $sum_of_all_ok = $sum_of_all_ok + $done_sql;

        if ( $priority_sql == 3 ) {

            # sum -> all priorities
            my $result2 = q{};
            $result2 .=
                '<tr><td class="table" style="text-align:right;"><a href="'
              . $script_name
              . '?project='
              . $param_project
              . '&amp;view=';
            $result2 .= 'all">all priorities';
            $result2 .=
                '</a></td><td class="table" style="text-align:right;">'
              . $sum_of_all
              . '</td><td class="table" style="text-align:right;">'
              . $sum_of_all_ok
              . '</td></tr>' . "\n";

            $result = $result2 . $result;
        }

    }

    return ($result);
}

####################################################################
# Show table with todo, description of errors (all,high,middle,low)
####################################################################

sub get_number_error_and_desc_by_prio {
    my ($prio)   = @_;
    my $result   = q{};
    my $sth;
    my $dbh      = connect_database();

    $column_orderby = 'name_trans' if ( $column_orderby eq q{} );
    $column_orderby = 'name_trans' if ( $param_orderby eq 'description' );
    $column_orderby = 'id'         if ( $param_orderby eq 'id' );
    $column_orderby = 'prio'       if ( $param_orderby eq 'priority' );

    if ( $param_project =~
/alswiki|barwiki|enwiktionary|fawiki|frwikiversity|hrwiki|ruwiktionary|simplewiki|svwikisource|svwiktionary/
      )
    {
        $column_orderby = 'name' if ( $column_orderby eq 'name_trans' );
    }

    $result .= $lang_dir;
    $result .= '<tr>';

    # SHOW ONE PRIORITY FROM ONE PROJECT
    if ( $prio > 0 ) {
        $result .= '<th class="table">To-do</th>';
        $result .= '<th class="table">Done</th>';

        #--------- DESCRIPTION

        $result .= '<th class="table">Description';
        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view='
          . $param_view
          . '&amp;orderby=description&amp;sort=asc">↑</a>';
        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view='
          . $param_view
          . '&amp;orderby=description&amp;sort=desc">↓</a>';
        $result .= '</th>';

        #--------- ID

        $result .= '<th class="table">ID';

        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view='
          . $param_view
          . '&amp;orderby=id&amp;sort=asc">↑</a>';
        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view='
          . $param_view
          . '&amp;orderby=id&amp;sort=desc">↓</a>';
        $result .= '</th>';

        $result .= '</tr>' . "\n";

        #--------- Main Table

        $sth = $dbh->prepare( q{SELECT IFNULL(errors, '') todo, IFNULL(done, '') ok, name, name_trans, id, prio FROM cw_overview_errors WHERE prio = ? AND PROJECT = ? ORDER BY }
            . $column_orderby . q{ }
            . $column_sort . ', name;' )
          or die "Problem with statement: $DBI::errstr\n";
        $sth->execute( $prio, $param_project )
          or die "Cannot execute: $sth->errstr\n";
    }

    # SHOW ALL PRIORITIES FROM ONE PROJECT
    elsif ( $prio == 0 and $param_project ne 'all' ) {

        #--------- PRIORITY

        $result .= '<th class="table">Priority';
        $result .= '<a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view='
          . $param_view
          . '&amp;orderby=priority&amp;sort=asc">↑</a>';
        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view='
          . $param_view
          . '&amp;orderby=priority&amp;sort=desc">↓</a>';
        $result .= '</th>';

        #--------- TO-DO & DONE

        $result .= '<th class="table">To-do</th>';
        $result .= '<th class="table">Done</th>';

        #--------- DESCRIPTION

        $result .= '<th class="table">Description';
        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view='
          . $param_view
          . '&amp;orderby=description&amp;sort=asc">↑</a>';
        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view='
          . $param_view
          . '&amp;orderby=description&amp;sort=desc">↓</a>';
        $result .= '</th>';

        #--------- ID

        $result .= '<th class="table">ID';

        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view='
          . $param_view
          . '&amp;orderby=id&amp;sort=asc">↑</a>';
        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view='
          . $param_view
          . '&amp;orderby=id&amp;sort=desc">↓</a>';
        $result .= '</th>';

        $result .= '</tr>' . "\n";

        #--------- MAIN TABLE

        $sth = $dbh->prepare( q{SELECT IFNULL(errors, '') todo, IFNULL(done, '') ok, name, name_trans, id, prio FROM cw_overview_errors WHERE project = ? ORDER BY }
            . $column_orderby . q{ }
            . $column_sort . q{;} ) 
          or die "Problem with statement: $DBI::errstr\n";
        $sth->execute( $param_project )
          or die "Cannot execute: $sth->errstr\n";
    }

    # SHOW ALL PRIORITIES FROM ALL PROJECTS
    elsif ( $prio == 0 and $param_project eq 'all' ) {
        $sth = $dbh->prepare( q{SELECT IFNULL(errors, '') todo, IFNULL(done, '') ok, name, name_trans, id, prio FROM cw_overview_errors ORDER BY name_trans, name;} )
          or die "Problem with statement: $DBI::errstr\n";
        $sth->execute
          or die "Cannot execute: $sth->errstr\n";
    }

    my ( $errors_sql, $done_sql, $ok_sql, $name_sql, $trans_sql,  $id_sql,   $prio_sql);

    $sth->bind_col( 1, \$errors_sql );
    $sth->bind_col( 2, \$ok_sql );
    $sth->bind_col( 3, \$name_sql );
    $sth->bind_col( 4, \$trans_sql );
    $sth->bind_col( 5, \$id_sql );
    $sth->bind_col( 6, \$prio_sql );

    while ( $sth->fetchrow_arrayref ) {

        if ( !defined($trans_sql) ) {
            $trans_sql = q{};
        }

        my $headline = $name_sql;
        if ( $trans_sql ne q{} ) {
            $headline = $trans_sql;
        }

        my $priority;
        if ( $prio_sql > -1 ) {
            $priority = 'off'    if ( $prio_sql == 0 );
            $priority = 'high'   if ( $prio_sql == 1 );
            $priority = 'middle' if ( $prio_sql == 2 );
            $priority = 'low'    if ( $prio_sql == 3 );

            $result .= '<tr>';
            if ( $prio == 0 ) {
                $result .=
                  '<td class="table" style="text-align:center;">'
                  . $priority . '</td>';
            }
            $result .=
              '<td class="table" style="text-align:right;">'
              . $errors_sql . '</td>';
            $result .=
              '<td class="table" style="text-align:right;">'
              . $ok_sql . '</td>';
            $result .=
                '<td class="table"><a href="'
              . $script_name
              . '?project='
              . $param_project
              . '&amp;view=only&amp;id='
              . $id_sql
              . '">'
              . $headline
              . '</a></td>';
            $result .=
              '<td class="table" style="text-align:right;">'
              . $id_sql . '</td>';
            $result .= '</tr>' . "\n";
        }
    }
    $result .= '</table>' . "\n\n";

    return ($result);
}

###########################################################################

sub get_headline {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    my $sth = $dbh->prepare(
'SELECT name, name_trans FROM cw_overview_errors WHERE id= ? AND project= ?;' )
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $error, $param_project )
      or die "Cannot execute: $sth->errstr\n";

    my ( $name_sql, $name_trans_sql );
    $sth->bind_col( 1, \$name_sql );
    $sth->bind_col( 2, \$name_trans_sql );

    $sth->fetchrow_arrayref;

    if ( !defined($name_sql) ) {
        $name_sql = q{};
    }
    if ( !defined($name_trans_sql) ) {
        $name_trans_sql = q{};
    }

    if ( $name_trans_sql ne q{} ) {
        $result = $name_trans_sql;    # Translated text
    }
    else {
        $result = $name_sql;          # English text
    }

    return ($result);
}

###########################################################################

sub get_description {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    my $sth = $dbh->prepare(
'SELECT text, text_trans FROM cw_overview_errors WHERE id= ? AND project= ?;' )
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $error, $param_project )
      or die "Cannot execute: $sth->errstr\n";

    my ( $text_sql, $text_trans_sql );
    $sth->bind_col( 1, \$text_sql );
    $sth->bind_col( 2, \$text_trans_sql );

    $sth->fetchrow_arrayref;

    if ( !defined($text_sql) ) {
        $text_sql = q{};
    }
    if ( !defined($text_trans_sql) ) {
        $text_trans_sql = q{};
    }

    if ( $text_trans_sql ne q{} ) {
        $result = $text_trans_sql;    # Translated text
    }
    else {
        $result = $text_sql;          # English text
    }

    return ($result);
}

###########################################################################

sub get_prio_of_error {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    my $sth = $dbh->prepare(
        'SELECT prio FROM cw_overview_errors WHERE id= ? AND project= ?;')
      or die "Problem with statement: $DBI::errstr\n";
    $sth->execute( $error, $param_project )
      or die "Cannot execute: $sth->errstr\n";

    $result = $sth->fetchrow();

    return ($result);
}

##########################################################################
## SHOW TABLE FOR ONLY ONE ERROR FOR ONE PROJECT
##########################################################################

sub get_article_of_error {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    $column_orderby = q{}      if ( $column_orderby eq q{} );
    $column_orderby = 'title'  if ( $param_orderby eq 'article' );
    $column_orderby = 'notice' if ( $param_orderby eq 'notice' );
    $column_orderby = 'more'   if ( $param_orderby eq 'more' );
    $column_orderby = 'found'  if ( $param_orderby eq 'found' );

    #------------------- ← 0 bis 25 →

    $result .= '<p>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $offset_lower
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby='
      . $param_orderby
      . '&amp;sort='
      . $param_sort
      . '">←</a>';
    $result .= q{ } . $param_offset . ' to ' . $offset_end . q{ };
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $offset_higher
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby='
      . $param_orderby
      . '&amp;sort='
      . $param_sort
      . '">→</a>';
    $result .= ' &nbsp;&nbsp;(';
    my $result_temp =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit=';
    my $result_temp_end =
      '&amp;orderby=' . $param_orderby . '&amp;sort=' . $param_sort;
    $result .= $result_temp . '25' . $result_temp_end . '">25</a>|';
    $result .= $result_temp . '50' . $result_temp_end . '">50</a>|';
    $result .= $result_temp . '100' . $result_temp_end . '">100</a>|';
    $result .= $result_temp . '200' . $result_temp_end . '">200</a>)';
    $result .= '</p>';

    #------------------- ARTICLE TITLE

    $result .= $lang_dir; 
    $result .= '<tr>';
    $result .= '<th class="table">Article';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=article&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=article&amp;sort=desc">↓</a>';
    $result .= '</th>';

    #------------------- EDIT

    $result .= '<th class="table">Edit</th>';

    #------------------- NOTICE

    $result .= '<th class="table">Notice';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=notice&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=notice&amp;sort=desc">↓</a>';
    $result .= '</th>';

    #------------------- MORE

    $result .= '<th class="table">More</th>';

    #------------------- FOUND

    $result .= '<th class="table">Found';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=found&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=only&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=found&amp;sort=desc">↓</a>';
    $result .= '</th>';

    #------------------- DONE

    $result .= '<th class="table">Done</th>';
    $result .= '</tr>' . "\n\n";

    #--------- Main Table

    my $row_style = q{};
    my $row_style_main;
   
    $column_orderby = 'title' if ( $column_orderby eq q{} );

    # Can't use placeholders for sort
    my $sth = $dbh->prepare( 'SELECT title, notice, found, project FROM cw_error WHERE error= ? AND project= ? AND ok=0 ORDER BY '
          . $column_orderby . q{ } 
          . $column_sort
          . ' LIMIT ?, ?;' )
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $error, $param_project, $param_offset, $param_limit )
      or die "Cannot execute: $sth->errstr\n";

    my ( $title_sql, $notice_sql, $found_sql, $project_sql );
    $sth->bind_col( 1, \$title_sql );
    $sth->bind_col( 2, \$notice_sql );
    $sth->bind_col( 3, \$found_sql );
    $sth->bind_col( 4, \$project_sql );

    while ( $sth->fetchrow_arrayref ) {

        if ( !defined($found_sql) ) {
            $found_sql = q{};
        }

#XXXXX
        # AMPERSAND SEPERATES VARIABLES ON URL SEQUENCE. CHANGE TO %26
        # CHANGE " to %22 and ' to $27
        # USE %20 FOR SPACES WHEN ACCESSING NON-WIKIPEDIA LINKS
        my $title_sql_amp = $title_sql;
        $title_sql_amp =~ s/%/%25/g;
        $title_sql_amp =~ s/&/%26/g;
        $title_sql_amp =~ s/\+/%2B/g;
        $title_sql_amp =~ s/ /%20/g;
        $title_sql_amp =~ s/\"/%22/g;
        $title_sql_amp =~ s/\'/%27/g;
        $title_sql_amp =~ s/\?/%3F/g;

        # USE _ FOR SPACES WHEN ACCESSING WIKIPEDIA LINKS
        my $title_sql_under = $title_sql_amp;
        $title_sql_under =~ tr/ /_/;

        my $article_project = $param_project;
        if ( $param_project eq 'all' ) {
            $article_project = $project_sql;
        }

        my $homepage = get_homepage($article_project);

        if ( $row_style eq q{} ) {
            $row_style      = 'style="background-color:#D0F5A9;"';
            $row_style_main = 'style="background-color:#D0F5A9; ';
        }
        else {
            $row_style      = q{};
            $row_style_main = 'style="';
        }

        $result .= '<tr>';
        $result .=
            '<td class="table" '
          . $row_style
          . '><a href="https://'
          . $homepage
          . '/wiki/'
          . $title_sql_under . '">'
          . $title_sql
          . '</a></td>';
        $result .=
            '<td class="table" '
          . $row_style
          . '><a href="https://'
          . $homepage
          . '/w/index.php?title='
          . $title_sql_under
          . '&amp;action=edit">edit</a></td>';

        if ( $param_id == 25 or $param_id == 78 ) {
            $notice_sql =~ s/&lt;br&gt;/\<br\>/;
        }

        # Allows for right-to-left and LTR text to play together correctly.
        if ( $bidi == 1 ) {
            $notice_sql = '<span style="unicode-bidi:embed;">'
              . $notice_sql
              . '</span>';
        }
        $result .=
          '<td class="table" ' . $row_style . '>' . $notice_sql . '</td>';
        $result .=
          '<td class="table" ' . $row_style_main . ' text-align:center;">';

        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $article_project
          . '&amp;view=detail&amp;title='
          . $title_sql_amp . '">'
          . 'more</a>';

        $result .= '</td>';
        $result .=
            '<td class="table" '
          . $row_style . '>'
          . time_string($found_sql) . '</td>';
        $result .=
          '<td class="table" ' . $row_style_main . ' text-align:center;">';
        $result .=
            '<a href="'
          . $script_name
          . '?project='
          . $article_project
          . '&amp;view=only&amp;id='
          . $error
          . '&amp;title='
          . $title_sql_amp
          . '&amp;offset='
          . $param_offset
          . '&amp;limit='
          . $param_limit;

        if ( $param_orderby ne q{} ) {
            $result .= '&amp;orderby=' . $param_orderby;
        }
        if ( $param_sort ne q{} ) {
            $result .= '&amp;sort=' . $param_sort;
        }
        $result .= '">Done</a></td></tr>' . "\n\n";

    }
    $result .= '</table>' . "\n\n";

    return ($result);
}

###########################################################################

sub get_done_article_of_error {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    # show all done articles of one error

    $column_orderby = 'title'  if ( $column_orderby eq q{} );
    $column_orderby = 'title'  if ( $param_orderby eq 'article' );
    $column_orderby = 'notice' if ( $param_orderby eq 'notice' );
    $column_orderby = 'more'   if ( $param_orderby eq 'more' );
    $column_orderby = 'found'  if ( $param_orderby eq 'found' );

    #------------------- ← 0 to 25 →

    $result .= '<p>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $offset_lower
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby='
      . $param_orderby
      . '&amp;sort='
      . $param_sort
      . '">←</a>';
    $result .= q{ } . $param_offset . ' to ' . $offset_end . q{ };
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $offset_higher
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby='
      . $param_orderby
      . '&amp;sort='
      . '">→</a>';
    $result .= ' &nbsp;&nbsp;(';
    my $result_temp =
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit=';
    my $result_temp_end =
      '&amp;orderby=' . $param_orderby . '&amp;sort=' . $param_sort;
    $result .= $result_temp . '25' . $result_temp_end . '">25</a>|';
    $result .= $result_temp . '50' . $result_temp_end . '">50</a>|';
    $result .= $result_temp . '100' . $result_temp_end . '">100</a>|';
    $result .= $result_temp . '200' . $result_temp_end . '">200</a>)';

    $result .= '</p>';

    #------------------- ARTICLE TITLE

    $result .= $lang_dir; 
    $result .= '<tr>';
    $result .= '<th class="table">Article';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=article&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=article&amp;sort=desc">↓</a>';
    $result .= '</th>';

    #------------------- VERSION

    $result .= '<th class="table">Version</th>';

    #------------------- NOTICE

    $result .= '<th class="table">Notice';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=notice&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=notice&amp;sort=desc">↓</a>';
    $result .= '</th>';

    #------------------- FOUND

    $result .= '<th class="table">Found';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=found&amp;sort=asc">↑</a>';
    $result .=
        '<a href="'
      . $script_name
      . '?project='
      . $param_project
      . '&amp;view=onlydone&amp;id='
      . $param_id
      . '&amp;offset='
      . $param_offset
      . '&amp;limit='
      . $param_limit
      . '&amp;orderby=found&amp;sort=desc">↓</a>';
    $result .= '</th>';

    #------------------- DONE

    $result .= '<th class="table">Done</th>';
    $result .= '</tr>' . "\n\n";

    #--------- Main Table

    my $row_style = q{};
    my $row_style_main;
    my $sth;

    if ( $param_project ne 'all' ) {
        $sth = $dbh->prepare(
            'SELECT title, notice, found, project FROM cw_error
             WHERE error= ? AND ok=1 AND project = ? ORDER BY '
              . $column_orderby . q{ } 
              . $column_sort
              . ' LIMIT ?, ? ;' )
          or die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute( $error, $param_project, $param_offset, $param_limit )
          or die "Cannot execute $sth->errstr\n";

    }
    else {
        $sth = $dbh->prepare(
            'SELECT title, notice, found, project FROM cw_error 
             WHERE error= ? AND ok=1 ORDER BY '
              . $column_orderby . q{ } 
              . $column_sort
              . ' LIMIT ?, ? ;' )
          or die "Can not prepare statement: $DBI::errstr\n";
        $sth->execute( $error, $param_offset, $param_limit )
          or die "Cannot execute: $sth->errstr\n";
    }

    my ( $title_sql, $notice_sql, $found_sql, $project_sql );
    $sth->bind_col( 1, \$title_sql );
    $sth->bind_col( 2, \$notice_sql );
    $sth->bind_col( 3, \$found_sql );
    $sth->bind_col( 4, \$project_sql );

    while ( $sth->fetchrow_arrayref ) {
        $found_sql = q{} if ( !defined $found_sql );

        my $title_sql_under = $title_sql;
        $title_sql_under =~ tr/ /_/;
        $title_sql_under =~ s/&/%26/g;
        $title_sql_under =~ s/\"/%22/g;
        $title_sql_under =~ s/\+/%2B/g;
        $title_sql_under =~ s/\?/%3F/g;

        my $article_project = $param_project;
        if ( $param_project eq 'all' ) {
            $article_project = $project_sql;
        }

        my $homepage = get_homepage($article_project);

        if ( $row_style eq q{} ) {
            $row_style = 'style="background-color:#D0F5A9;"';
            $row_style_main =
              'style="background-color:#D0F5A9; text-align:center;"';
        }
        else {
            $row_style      = q{};
            $row_style_main = 'style="text-align:center;"';
        }

        $result .= '<tr>';
        $result .=
            '<td class="table" '
          . $row_style
          . '><a href="https://'
          . $homepage
          . '/wiki/'
          . $title_sql_under . '">'
          . $title_sql
          . '</a></td>';
        $result .=
            '<td class="table" '
          . $row_style_main
          . '><a href="https://'
          . $homepage
          . '/w/index.php?title='
          . $title_sql_under
          . '&amp;action=history">history</a></td>';

        $result .=
            '<td class="table" '
          . $row_style;
        if ( $bidi == 1 ) {
            $result .= '><span style="unicode-bidi:embed;">'
              . $notice_sql
              . '</span></td>';
        }
        else {
            $result .= q{<} 
              . $notice_sql
              . '</td>';
        }
        $result .=
            '<td class="table" '
          . $row_style . '>'
          . time_string($found_sql) . '</td>';
        $result .= '<td class="table" ' . $row_style_main . '>';

        $result .= 'ok';
        $result .= '</td></tr>' . "\n\n";

    }
    $result .= '</table>' . "\n\n";

    return ($result);
}

###########################################################################

sub get_article_of_error_for_bots {
    my ($error) = @_;
    my $result  = q{};
    my $dbh     = connect_database();

    my $sth = $dbh->prepare(
'SELECT title FROM cw_error WHERE error= ? AND project= ? AND ok=0 LIMIT ?, ?;')
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $error, $param_project, $param_offset, $param_limit )
      or die "Cannot execute: $sth->errstr\n";

    $result .= '<pre>' . "\n";

    my ($title_sql);
    $sth->bind_col( 1, \$title_sql );

    while ( $sth->fetchrow_arrayref ) {
        $result .= $title_sql . "\n";
    }

    $result .= '</pre>' . "\n";

    return ($result);
}

###########################################################################
## OPEN DATABASE
###########################################################################

sub connect_database {

    my ( $dbh, $dsn, $user, $password );

    $dsn =
'DBI:mysql:s51080__checkwiki_p:tools-db;mysql_read_default_file=../../replica.my.cnf';
    $dbh = DBI->connect( $dsn, $user, $password, { mysql_enable_utf8 => 1 } )
      or die( 'Could not connect to database: ' . DBI::errstr() . "\n" );

    return ($dbh);
}

###########################################################################

sub get_all_error_of_article {
    my ($id)   = @_;
    my $result = q{};
    my $dbh    = connect_database();

    $result .= $lang_dir;
    $result .= '<tr>';
    $result .= '<th class="table">Error</th>';
    $result .= '<th class="table">Description</th>';
    $result .= '<th class="table">Notice</th>';
    $result .= '<th class="table">Done</th>';
    $result .= '</tr>' . "\n\n";

    my $sth = $dbh->prepare(
'SELECT error, notice, title, ok FROM cw_error  WHERE title= ? AND Project= ? ORDER BY error')
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $param_title, $param_project )
      or die "Cannot execute: $sth->errstr\n";

    my ( $error_sql, $notice_sql, $title_sql, $ok_sql );
    $sth->bind_col( 1, \$error_sql );
    $sth->bind_col( 2, \$notice_sql );
    $sth->bind_col( 3, \$title_sql );
    $sth->bind_col( 4, \$ok_sql );

    while ( $sth->fetchrow_arrayref ) {

        my $stt = $dbh->prepare(
            'SELECT name_trans FROM cw_overview_errors WHERE project=? and id=?'
        );
        $stt->execute( $param_project, $error_sql )
          or die "Cannot execute: $stt->errstr\n";
        my @error_description = $stt->fetchrow_array;

        my $title_sql_amp = $title_sql;
        $title_sql_amp =~ s/ /%20/g;
        $title_sql_amp =~ s/&/%26/g;
        $title_sql_amp =~ s/\+/%2B/g;
        $title_sql_amp =~ s/\?/%3F/g;
        $title_sql_amp =~ tr/ /_/;

        $result .= '<tr>';
        $result .=
            '<td class="table" style="text-align:center;"><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=only&amp;id='
          . $error_sql . '">';
        $result .= '</a>' . $error_sql . '</td>';
        $result .=
            '<td class="table"><a href="'
          . $script_name
          . '?project='
          . $param_project
          . '&amp;view=only&amp;id='
          . $error_sql
          . '">'
          . $error_description[0]
          . '</a></td>';
        if ( $bidi == 1 ) {
            $result .=
                '<td class="table"><span style="unicode-bidi:embed;">'
              . $notice_sql
              . '</span></td>';
        }
        else {
            $result .=
                '<td class="table">'
              . $notice_sql
              . '</td>';
        }

        $result .= '<td class="table" style="text-align:right;">';

        if ( $ok_sql eq '0' ) {
            $result .=
                '<a href="'
              . $script_name
              . '?project='
              . $param_project
              . '&amp;view=detail&amp;id='
              . $error_sql
              . '&amp;title='
              . $title_sql_amp
              . '">Done</a>';
        }
        else {
            $result .= 'ok';
        }
        $result .= '</td>';
        $result .= '</tr>' . "\n";

    }
    $result .= '</table>' . "\n\n";

    return ($result);
}

###########################################################################

sub time_string {
    my ($timestring) = @_;
    my $result = q{};

    if ( $timestring ne q{} ) {
        $result = $timestring . '---';
        $result = $timestring;
        $result =~ s/ /&nbsp;/g;    # SYNTAX HIGHLIGHTING
    }

    return ($result);
}

###########################################################################

sub get_homepage {
    my ($result) = @_;

    if (
        !(
               $result =~ s/^nds_nlwiki$/nds-nl.wikipedia.org/
            || $result =~ s/^commonswiki$/commons.wikimedia.org/
            || $result =~ s/^([[:lower:]]+)wiki$/$1.wikipedia.org/
            || $result =~ s/^([[:lower:]]+)wikisource$/$1.wikisource.org/
            || $result =~ s/^([[:lower:]]+)wikiversity$/$1.wikiversity.org/
            || $result =~ s/^([[:lower:]]+)wiktionary$/$1.wiktionary.org/
        )
      )
    {
        die(    'Could not calculate server name for project'
              . $param_project
              . "\n" );
    }

    return ($result);
}

###########################################################################

sub get_style {
    my $result = q{<style type="text/css">
body {
    font-family: Verdana, Tahoma, Arial, Helvetica, sans-serif;
    font-size:14px;
    font-style:normal;

    background-color:white;
    color:#222222;
    text-decoration:none;
    line-height:normal;
    font-weight:normal;
    font-variant:normal;
    text-transform:none;
    margin-left:5%;
    margin-right:5%;
    }

h1  {
    font-size:20px;
    }

h2  {
	font-size:16px;
	}

a   {
	color:#2f72b0;
	font-weight:bold;

	/* without underline */
	text-decoration:none;
	}

a:hover {
	background-color:#ffdeff;
	color:red;
	}

.nocolor{
	background-color:white;
	color:white;
	}

a:hover.nocolor{
	background-color:white;
	color:white;
	}

.table{
	font-size:12px;

	vertical-align:top;

	border-width:thin;
  	border-style:solid;
  	border-color:blue;
  	background-color:#F2F2F2;

	padding-top:2px;
	padding-bottom:2px;
	padding-left:5px;
	padding-right:5px;

  	/* small border */
  	border-collapse:collapse;

    /* no wrap
	white-space:nowrap;*/

  	}

</style>};
    return ($result);
}
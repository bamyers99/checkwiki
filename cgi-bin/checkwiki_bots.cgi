#! /usr/bin/env perl

###########################################################################
##
##         FILE: checkwiki_bots.pl
##
##        USAGE: ./checkwiki_bots.pl
##
##  DESCRIPTION: Method for WikipediaCleaner tor retrieve articles
##
##       AUTHOR: Stefan Kühn, Nicolas Vervelle, Bryan White
##      LICENCE: GPLv3
##      VERSION: 2017-01-06
##
###########################################################################

use strict;
use warnings;
use lib
'/data/project/checkwiki/perl5/perlbrew/perls/perl-5.24.0/lib/site_perl/5.24.0/';

use CGI::Lite;
use CGI::Carp qw(fatalsToBrowser set_message);
use DBI;
use Time::HiRes qw(usleep);

binmode( STDOUT, ':encoding(UTF-8)' );

###########################################################################
## GET PARAMETERS FROM CGI
###########################################################################

my $cgi  = CGI::Lite->new();
my $data = $cgi->parse_form_data;

my $param_project = $data->{project};    # Project
my $param_action  = $data->{action};     # Action requested: list, mark
my $param_id      = $data->{id};         # Error number requested
my $param_offset  = $data->{offset};     # Offset for the list of articles
my $param_limit   = $data->{limit};      # Limit number of articles in the list
my $param_title   = $data->{title};      # Article title

$param_project = q{} if ( !defined $param_project );
$param_action  = q{} if ( !defined $param_action );
$param_id      = q{} if ( !defined $param_id );
$param_title   = q{} if ( !defined $param_title );
$param_offset  = q{} if ( !defined $param_offset );
$param_limit   = q{} if ( !defined $param_limit );

if ( $param_offset !~ /^[0-9]+$/ ) {
    $param_offset = 0;
}

if ( $param_limit !~ /^[0-9]+$/ ) {
    $param_limit = 25;
}

if ( $param_project !~ /^[a-z]+$/ ) {
    die "An invalid project has been entered\n";
}

if ( $param_id < 1 or $param_id > 113 ) {
    die "An invalid error id  has been entered\n";
}

# Maximum number of articles to return
if ( $param_limit > 10_000 ) {
    $param_limit = 10_000;
}

##########################################################################
## MAIN PROGRAM
##########################################################################

# List articles
if (    $param_project ne q{}
    and $param_action eq 'list'
    and $param_id =~ /^[0-9]+$/ )
{
    list_articles();
}

# Mark error as fixed
elsif ( $param_project ne q{}
    and $param_action eq 'mark'
    and $param_id =~ /^[0-9]+$/
    and $param_title ne q{} )
{
    mark_article_done();
}
else {
    show_usage();
}

##########################################################################
## LIST ARTICLES
##########################################################################

sub list_articles {
    my $dbh = connect_database();

    my $sth = $dbh->prepare(
'SELECT title FROM cw_error WHERE error = ? AND project = ? AND ok=0 LIMIT ?, ?;'
    ) or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $param_id, $param_project, $param_offset, $param_limit )
      or die "Cannot execute: $sth->errstr\n";

    print "Content-type: text/plain;charset=UTF-8\n\n";

    my $title_sql;
    $sth->bind_col( 1, \$title_sql );

    while ( $sth->fetchrow_arrayref ) {
        print "title=$title_sql\n";
    }

    # Need to sleep for WPCleaner, else it bombs
    usleep(333_000);

    return ();
}

##########################################################################
## MARK ARTICLE AS DONE
##########################################################################

sub mark_article_done {
    my $dbh = connect_database();

    my $sth = $dbh->prepare(
        'UPDATE cw_error SET ok=1 WHERE title= ? AND error= ? And project = ?;')
      or die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute( $param_title, $param_id, $param_project )
      or die "Cannot execute: $sth->errstr\n";

    #Need to sleep for WPCleaner, else it bombs
    usleep(250_000);

    print "Content-type: text/text\n\n";
    print "Article $param_title has been marked as done.";

    return ();
}

##########################################################################
##  SHOW SCRIPT USAGE
##########################################################################

sub show_usage {

    print "Content-type: text/text\n\n";
    print "# There has been an error.\n\n";
    print "This script can be used with the following parameters:\n";
    print "  project=  : name of the project (enwiki, ...)\n";
    print "  id=       : Error number (04, 10, 80, ...)\n";
    print "  title=    : title of the article that has been fixed\n";
    print "  action=   : action requested, among the following values:\n";
    print
"    list: list articles for the given improvement. The following parameters can also be used:\n";
    print
"    mark: mark an article as fixed for the given improvement. The following parameters can also be used:\n";
    print "  offset=   : offset in the list of articles\n";
    print "  limit=    : maximum number of articles in the list\n";

    return ();
}

##########################################################################
##  CONNECT TO THE DATABASE
##########################################################################

sub connect_database {

    my ( $dbh, $dsn, $user, $password );

    $dsn =
'DBI:mysql:s51080__checkwiki_p:tools-db;mysql_read_default_file=../../replica.my.cnf';
    $dbh = DBI->connect(
        $dsn, $user,
        $password,
        {
            mysql_enable_utf8mb4 => 1,
        }
    ) or die("Could not connect to database: DBI::errstr()\n");

	$dbh->do('SET NAMES utf8mb4')
	   or die($dbh->errstr);

    return ($dbh);
}
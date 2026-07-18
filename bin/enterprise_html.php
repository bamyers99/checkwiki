<?php
/**
 Copyright 2026 Myers Enterprises II

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 
 https://enterprise.wikimedia.com/docs/snapshot/
 https://enterprise.wikimedia.com/docs/data-dictionary/
 
 toolforge jobs run enterprisehtml --image php8.4 --command "php bin/enterprise_html.php nlwiki"
 
 */

DEFINE('SUPPLEMENT_TYPE_HASREF', 1);
DEFINE('SUPPLEMENT_SOURCE', 1);

if ($argc < 2) {
    echo 'Usage: enterprise_html.php "project_name or monthly"';
    exit;
}

$daily_projects = ['enwiki', 'dewiki', 'eswiki', 'frwiki', 'arwiki', 'cswiki', 'plwiki', 'bnwiki', 'nlwiki', 'nowiki', 'cawiki', 'hewiki',
    'ruwiki', 'itwiki', 'ptwiki', 'ukwiki'];

$monthly_projects = ['alswiki', 'barwiki', 'dawiki', 'elwiki' ,'nds_nlwiki' ,'scowiki'];

$project_name = $argv[1];

if ($project_name == 'monthly') $project_list = $monthly_projects;
else $project_list = [$project_name];

$hndl = fopen('/data/project/checkwiki/checkwiki.cfg', 'r');
$config = [];
$add_count = 0;
$article_count = 0;

while (! feof($hndl)) {
    $buffer = rtrim(fgets($hndl));
    if (empty($buffer)) continue;
    
    $parts = explode(' ', $buffer, 2);
    $key = substr($parts[0], 2); // skip --
    $value = $parts[1];
    
    $config[$key] = $value;
}

fclose($hndl);

$dbh_wikidata = new PDO("mysql:host={$config['host']};dbname={$config['database']};charset=utf8mb4", $config['user'], $config['password']);
$dbh_wikidata->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

foreach ($project_list as $project_name) {
    process_project($project_name);
}

echo "Article count: $article_count  Add count: $add_count\n";

/**
 * Process a project
 * 
 * @param string $project_name
 */
function process_project($project_name)
{
    global $dbh_wikidata, $chunked;
    $responseCode = 0;
    
    // Lookup project id
    $sql = 'SELECT ID FROM cw_overview WHERE Project = ?';
    $sth = $dbh_wikidata->prepare($sql);
    $sth->execute([$project_name]);
    $results = $sth->fetchAll(PDO::FETCH_NUM);
    
    if (count($results) != 1) {
        fputs(STDERR, "Project not found = $project_name\n");
        return;
    }
    
    $project_num = $results[0][0];
    
    $sql = "DELETE FROM cw_supplement WHERE ProjectNo = $project_num AND Source = " . SUPPLEMENT_SOURCE;
    $dbh_wikidata->exec($sql);
    
    // Retrieve the chunk list
    $url = "https://api.enterprise.wikimedia.com/v2/snapshots/{$project_name}_namespace_0/chunks";
    
    $chunk_list = retrieve_url($url, 'string', '', $responseCode);
    if ($responseCode != 200) {
        fputs(STDERR, "Error retrieving $project_name chunk list: $responseCode\n");
        return;
    }
    
    $chunk_list = json_decode($chunk_list, true);
    
    foreach ($chunk_list as $chunk) {
        $chunk_id = $chunk['identifier'];
        $url = "https://api.enterprise.wikimedia.com/v2/snapshots/{$project_name}_namespace_0/chunks/$chunk_id/download";
        $outfile = 'enterprise_html_chunk.tar.gz';
        
        retrieve_url($url, 'file', $outfile, $responseCode);
        
        if ($responseCode != 200) {
            fputs(STDERR, "Error retrieving $project_name $chunk_id data: $responseCode\n");
            unlink($outfile);
            return;
        }
        
        process_chunk($project_num, $outfile);
        
        unlink($outfile);
        /* remove */
        //break;
    }
}

/**
 * Process a chunk
 * 
 * @param int $project_num
 * @param string $infile
 */
function process_chunk($project_num, $infile)
{
    global $dbh_wikidata, $add_count, $article_count;
    static $skip_regexes = [
        '/<ref(?:\s*>|\s+name)/i',
        '/<\s*+references\s*+(?:\/>|>|group|responsive)/i',
        '/\{\{\s*ref(?:begin|end|list)/i'
    ];
    
    $sql = "INSERT IGNORE INTO cw_supplement VALUES ($project_num,BINARY ?," . SUPPLEMENT_TYPE_HASREF . ',' . SUPPLEMENT_SOURCE . ",'')";
    $sth = $dbh_wikidata->prepare($sql);
    
    $handle = gzopen($infile, 'rb');
    
    while (!gzeof($handle)) {
        ++$article_count;
        $buffer = gzgets($handle);
        $page = json_decode($buffer, true);
        
        $wikitext_body = isset($page['article_body']['wikitext']) ? $page['article_body']['wikitext'] : false;
        
        if ($wikitext_body === false) continue;
        
        foreach ($skip_regexes as $skip_regex) {
            if (preg_match($skip_regex, $wikitext_body)) continue 2;
        }
        
        $html_body = isset($page['article_body']['html']) ? $page['article_body']['html'] : false;
        
        if ($html_body === false) continue;
        
        // Look for <div class="mw-references-wrap" "autoGenerated":true
        
        $found_class = preg_match('/<div\s+class\s*=\s*"[^"]*mw-references-wrap[^>]+"autoGenerated":true/', $html_body);
        
        if (! $found_class) continue;
        
        $sth->execute([$page['name']]);
        ++$add_count;
        
        //if ($page['name'] == 'Académie') print_r($page);
        
        //if ($page['name'] == 'Académie') exit;
    }
    
    gzclose($handle);
}

/**
 * Retrieve a url
 * 
 * @param string $url
 * @param string $fetch_type file or string
 * @param string $output_file_path required for type file
 */
function retrieve_url($url, $fetch_type, $output_file_path = '', &$responseCode)
{
    $ch = curl_init();
    
    if ($fetch_type == 'file') $fp = fopen($output_file_path, 'w');
    
    curl_setopt($ch, CURLOPT_HEADER, 0);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, 1);
    curl_setopt($ch, CURLOPT_USERAGENT, 'Checkwiki (checkwiki.support@tools.wmflabs.org)');
    curl_setopt($ch, CURLOPT_URL, $url);
    
    if ($fetch_type == 'file') curl_setopt($ch, CURLOPT_FILE, $fp);
    else curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
    
    $page = curl_exec($ch);
    
    $responseCode = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    
    if ($fetch_type == 'file') fclose($fp);
    
    curl_close($ch);
    
    return $page;
}

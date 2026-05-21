import Foundation

struct HTMLReportGenerator {

    static func generate(from reports: [SetlistReport], denylistGenres: Set<String> = [], reportName: String? = nil) -> String {
        let allEntries: [(setlistName: String, entry: SetlistReportEntry)] = reports.flatMap { r in
            r.entries.map { (setlistName: r.name, entry: $0) }
        }

        // Stats
        let totalTracks = allEntries.count
        let playedTracks = allEntries.filter { $0.entry.isPlayed }.count
        let totalSeconds = allEntries.compactMap { $0.entry.duration }.reduce(0, +)
        let tandaEntries = allEntries.filter { (_, e) in
            denylistGenres.isEmpty || denylistGenres.contains(e.genre.trimmingCharacters(in: .whitespaces).lowercased())
        }
        let years = tandaEntries.compactMap { $0.entry.year }
        let yearRange = years.isEmpty ? "—" : (years.min()! == years.max()! ? "\(years.min()!)" : "\(years.min()!) – \(years.max()!)")
        let uniqueArtists = Set(allEntries.map { $0.entry.artist }.filter { !$0.isEmpty }).count
        let uniqueGenres = Set(allEntries.map { $0.entry.genre }.filter { !$0.isEmpty }).count

        // Chart data
        var genreCounts: [String: Int] = [:]
        for (_, e) in allEntries {
            let g = e.genre.isEmpty ? "Unknown" : e.genre
            genreCounts[g, default: 0] += 1
        }
        var yearCounts: [Int: Int] = [:]
        for y in years { yearCounts[y, default: 0] += 1 }
        var artistCounts: [String: Int] = [:]
        for (_, e) in allEntries where !e.artist.isEmpty {
            artistCounts[e.artist, default: 0] += 1
        }

        let genresSorted = genreCounts.sorted { $0.value > $1.value }
        let yearsSorted = yearCounts.sorted { $0.key < $1.key }
        let topArtists = artistCounts.sorted { $0.value > $1.value }.prefix(10).reversed()

        // Per-genre breakdown (denylist genres only) — for breakdown charts
        let paletteColors = [
            "#14b8a6","#f59e0b","#3b82f6","#ec4899","#8b5cf6",
            "#10b981","#f97316","#06b6d4","#84cc16","#e11d48"
        ]
        var byGenreArtists: [String: [String: Int]] = [:]
        var byGenreYears: [String: [Int]] = [:]
        var byGenreSeconds: [String: TimeInterval] = [:]
        var byGenreCounts: [String: Int] = [:]
        for (_, e) in allEntries {
            let gKey = e.genre.trimmingCharacters(in: .whitespaces).lowercased()
            if !denylistGenres.isEmpty && !denylistGenres.contains(gKey) { continue }
            let gd = e.genre.isEmpty ? "Unknown" : e.genre
            if !e.artist.isEmpty { byGenreArtists[gd, default: [:]][e.artist, default: 0] += 1 }
            if let y = e.year { byGenreYears[gd, default: []].append(y) }
            if let d = e.duration { byGenreSeconds[gd, default: 0] += d }
            byGenreCounts[gd, default: 0] += 1
        }
        let statGenres = byGenreCounts.keys.sorted { (byGenreCounts[$0] ?? 0) > (byGenreCounts[$1] ?? 0) }
        var allArtistTotals: [String: Int] = [:]
        for am in byGenreArtists.values { for (a, c) in am { allArtistTotals[a, default: 0] += c } }
        let topGenreArtists = allArtistTotals.sorted { $0.value > $1.value }.prefix(6).map { $0.key }
        let genreArtistDatasets: [[String: Any]] = topGenreArtists.enumerated().map { idx, artist in
            let counts: [Int] = statGenres.map { genre in byGenreArtists[genre]?[artist] ?? 0 }
            return [
                "label": artist,
                "data": counts,
                "backgroundColor": paletteColors[idx % paletteColors.count],
                "borderRadius": 4
            ]
        }
        let genresWithYears = statGenres.filter { !(byGenreYears[$0] ?? []).isEmpty }
        let genreYearRanges: [[Int]] = genresWithYears.map { g in
            let ys = byGenreYears[g]!; return [ys.min()!, ys.max()!]
        }
        let genreTimeSeconds: [TimeInterval] = statGenres.map { byGenreSeconds[$0] ?? 0 }
        let genreTimeMinutes: [Double] = genreTimeSeconds.map { $0 / 60.0 }
        let genreTimeFormatted: [String] = genreTimeSeconds.map { formatDuration($0) }

        // Title
        let isMulti = reports.count > 1
        let reportTitle = reportName
            ?? (isMulti ? "Combined Setlist Report" : reports[0].name)

        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        let generatedOn = df.string(from: Date())

        // Setlist names subtitle
        let setlistSubtitle = isMulti
            ? reports.map { $0.name }.joined(separator: " · ")
            : df.string(from: reports[0].exportDate)

        // Logo — embedded as base64 data URI so the HTML is fully self-contained
        let logoDataURI: String = {
            guard let url = Bundle.main.url(forResource: "SetlistLogo", withExtension: "png"),
                  let data = try? Data(contentsOf: url) else { return "" }
            return "data:image/png;base64," + data.base64EncodedString()
        }()
        let logoTag = logoDataURI.isEmpty ? "" :
            "<img src=\"\(logoDataURI)\" alt=\"TangoDisplay\" class=\"w-14 h-14 flex-shrink-0\">"

        // JSON blobs
        let tableRows: [[String: Any]] = allEntries.map { (name, e) in
            [
                "setlist": name,
                "title": e.title,
                "artist": e.artist,
                "genre": e.genre,
                "year": e.year.map { String($0) } ?? "",
                "duration": e.duration.map { formatDuration($0) } ?? "",
                "played": e.isPlayed
            ]
        }
        let tableJSON = jsonString(tableRows)
        let genreLabels = jsonString(genresSorted.map { $0.key })
        let genreValues = jsonString(genresSorted.map { $0.value })
        let yearLabels = jsonString(yearsSorted.map { String($0.key) })
        let yearValues = jsonString(yearsSorted.map { $0.value })
        let artistLabels = jsonString(topArtists.map { $0.key })
        let artistValues = jsonString(topArtists.map { $0.value })
        let statGenreLabelsJSON = jsonString(statGenres)
        let genresWithYearsJSON = jsonString(genresWithYears)
        let genreArtistDatasetsJSON = jsonString(genreArtistDatasets)
        let genreYearRangesJSON = jsonString(genreYearRanges)
        let genreTimeMinutesJSON = jsonString(genreTimeMinutes)
        let genreTimeFormattedJSON = jsonString(genreTimeFormatted)

        // Per-setlist summary (multi only)
        let perSetlistRows: String = isMulti ? reports.map { r in
            let played = r.entries.filter { $0.isPlayed }.count
            let dur = r.entries.compactMap { $0.duration }.reduce(0, +)
            let ys = r.entries.compactMap { $0.year }
            let yr = ys.isEmpty ? "—" : (ys.min()! == ys.max()! ? "\(ys.min()!)" : "\(ys.min()!) – \(ys.max()!)")
            let artists = Set(r.entries.map { $0.artist }.filter { !$0.isEmpty }).count
            return """
            <tr class="border-b border-slate-700 hover:bg-slate-700/30">
              <td class="px-4 py-2 font-medium text-teal-400">\(htmlEscape(r.name))</td>
              <td class="px-4 py-2 text-center">\(r.entries.count)</td>
              <td class="px-4 py-2 text-center">\(played)</td>
              <td class="px-4 py-2 text-center">\(formatDuration(dur))</td>
              <td class="px-4 py-2 text-center">\(yr)</td>
              <td class="px-4 py-2 text-center">\(artists)</td>
            </tr>
            """
        }.joined() : ""

        let multiSetlistSection = isMulti ? """
        <section class="mb-8">
          <h2 class="text-lg font-semibold text-slate-300 mb-3">Per-Setlist Summary</h2>
          <div class="bg-slate-800 rounded-xl overflow-hidden border border-slate-700">
            <table class="w-full text-sm text-slate-300">
              <thead class="bg-slate-900/60 text-slate-400 uppercase text-xs">
                <tr>
                  <th class="px-4 py-3 text-left">Setlist</th>
                  <th class="px-4 py-3 text-center">Tracks</th>
                  <th class="px-4 py-3 text-center">Played</th>
                  <th class="px-4 py-3 text-center">Duration</th>
                  <th class="px-4 py-3 text-center">Years</th>
                  <th class="px-4 py-3 text-center">Artists</th>
                </tr>
              </thead>
              <tbody>\(perSetlistRows)</tbody>
            </table>
          </div>
        </section>
        """ : ""

        // Top 10 most played tracks across combined playlists (cortinas excluded)
        var trackCountMap: [String: (title: String, artist: String, genre: String, count: Int)] = [:]
        if isMulti {
            for (_, e) in allEntries {
                let genreKey = e.genre.trimmingCharacters(in: .whitespaces).lowercased()
                guard denylistGenres.isEmpty || denylistGenres.contains(genreKey) else { continue }
                let key = e.title.lowercased().trimmingCharacters(in: .whitespaces)
                       + "|||" + e.artist.lowercased().trimmingCharacters(in: .whitespaces)
                if let existing = trackCountMap[key] {
                    trackCountMap[key] = (existing.title, existing.artist, existing.genre, existing.count + 1)
                } else {
                    trackCountMap[key] = (e.title, e.artist, e.genre, 1)
                }
            }
        }
        let topPlayed = Array(
            trackCountMap.values
                .filter { $0.count >= 2 }
                .sorted {
                    if $0.count != $1.count { return $0.count > $1.count }
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                .prefix(10)
        )
        let topPlayedRows = topPlayed.enumerated().map { i, t -> String in
            "<tr class=\"border-b border-slate-700 hover:bg-slate-700/30\">" +
            "<td class=\"px-4 py-2 text-slate-500 tabular-nums\">\(i + 1)</td>" +
            "<td class=\"px-4 py-2 font-medium text-white max-w-[220px] truncate\" title=\"\(htmlEscape(t.title))\">\(htmlEscape(t.title))</td>" +
            "<td class=\"px-4 py-2 max-w-[160px] truncate\" title=\"\(htmlEscape(t.artist))\">\(htmlEscape(t.artist))</td>" +
            "<td class=\"px-4 py-2\">\(htmlEscape(t.genre))</td>" +
            "<td class=\"px-4 py-2 text-center\">" +
            "<span class=\"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-teal-500/20 text-teal-400\">\(t.count)×</span>" +
            "</td></tr>"
        }.joined(separator: "\n              ")
        let topPlayedSection = isMulti && !topPlayed.isEmpty ? """
        <section class="mb-8">
          <h2 class="text-lg font-semibold text-slate-300 mb-3">Top \(topPlayed.count) Most Played Tracks</h2>
          <div class="bg-slate-800 rounded-xl overflow-hidden border border-slate-700">
            <table class="w-full text-sm text-slate-300">
              <thead class="bg-slate-900/60 text-slate-400 uppercase text-xs">
                <tr>
                  <th class="px-4 py-3 text-left w-10">#</th>
                  <th class="px-4 py-3 text-left">Title</th>
                  <th class="px-4 py-3 text-left">Artist</th>
                  <th class="px-4 py-3 text-left">Genre</th>
                  <th class="px-4 py-3 text-center">Times Played</th>
                </tr>
              </thead>
              <tbody>\(topPlayedRows)</tbody>
            </table>
          </div>
        </section>
        """ : ""

        let genreBreakdownSection = statGenres.isEmpty ? "" : """
        <section class="mb-8">
          <h2 class="text-lg font-semibold text-slate-300 mb-3">Breakdown by Genre</h2>
          <div class="bg-slate-800 rounded-xl p-4 border border-slate-700 mb-4">
            <h3 class="text-sm font-medium text-slate-400 mb-3">Top Artists by Genre</h3>
            <div class="relative h-64">
              <canvas id="artistByGenreChart"></canvas>
            </div>
          </div>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
              <h3 class="text-sm font-medium text-slate-400 mb-3">Year Range by Genre</h3>
              <div class="relative h-48">
                <canvas id="yearRangeChart"></canvas>
              </div>
            </div>
            <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
              <h3 class="text-sm font-medium text-slate-400 mb-3">Time Played by Genre</h3>
              <div class="relative h-48">
                <canvas id="timeByGenreChart"></canvas>
              </div>
            </div>
          </div>
        </section>
        """

        let setlistColumnHeader = isMulti ? "<th class=\"px-4 py-3 text-left sortable cursor-pointer select-none\" data-col=\"setlist\">Setlist <span class=\"sort-icon\"></span></th>" : ""

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>\(htmlEscape(reportTitle))</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
            .sortable:hover { color: #2dd4bf; }
            .sort-asc::after { content: ' ▲'; font-size: 0.65em; }
            .sort-desc::after { content: ' ▼'; font-size: 0.65em; }
            #trackSearch:focus { outline: none; border-color: #14b8a6; }
            tr.hidden { display: none; }
          </style>
        </head>
        <body class="bg-slate-900 text-slate-100 min-h-screen">
          <div class="max-w-7xl mx-auto px-6 py-10">

            <!-- Header -->
            <header class="mb-8">
              <div class="flex items-start justify-between">
                <div class="flex items-center gap-4">
                  \(logoTag)
                  <div>
                    <h1 class="text-3xl font-bold text-white">\(htmlEscape(reportTitle))</h1>
                    <p class="text-slate-400 mt-1 text-sm">\(htmlEscape(setlistSubtitle))</p>
                  </div>
                </div>
                <div class="text-right text-xs text-slate-500 mt-1">
                  <div>Generated by TangoDisplay</div>
                  <div>\(htmlEscape(generatedOn))</div>
                </div>
              </div>
            </header>

            <!-- Summary Cards -->
            <section class="mb-8">
              <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4">
                \(card("Tracks", "\(totalTracks)"))
                \(card("Played", "\(playedTracks) / \(totalTracks)"))
                \(card("Duration", formatDuration(totalSeconds)))
                \(card("Years", yearRange))
                \(card("Artists", "\(uniqueArtists)"))
                \(card("Genres", "\(uniqueGenres)"))
              </div>
            </section>

            \(multiSetlistSection)

            <!-- Charts -->
            <section class="mb-8">
              <h2 class="text-lg font-semibold text-slate-300 mb-3">Analysis</h2>
              <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
                <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
                  <h3 class="text-sm font-medium text-slate-400 mb-3">Genre Breakdown</h3>
                  <div class="relative h-56">
                    <canvas id="genreChart"></canvas>
                  </div>
                </div>
                <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
                  <h3 class="text-sm font-medium text-slate-400 mb-3">Year Distribution</h3>
                  <div class="relative h-56">
                    <canvas id="yearChart"></canvas>
                  </div>
                </div>
                <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
                  <h3 class="text-sm font-medium text-slate-400 mb-3">Top Artists</h3>
                  <div class="relative h-56">
                    <canvas id="artistChart"></canvas>
                  </div>
                </div>
              </div>
            </section>

            \(genreBreakdownSection)

            \(topPlayedSection)

            <!-- Track Table -->
            <section>
              <div class="flex items-center justify-between mb-3">
                <h2 class="text-lg font-semibold text-slate-300">Track List</h2>
                <input id="trackSearch" type="text" placeholder="Filter tracks…"
                  class="bg-slate-800 border border-slate-600 rounded-lg px-3 py-1.5 text-sm text-slate-200 placeholder-slate-500 w-56 transition-colors">
              </div>
              <div class="bg-slate-800 rounded-xl overflow-hidden border border-slate-700">
                <table class="w-full text-sm text-slate-300" id="trackTable">
                  <thead class="bg-slate-900/60 text-slate-400 uppercase text-xs">
                    <tr>
                      <th class="px-4 py-3 text-left w-10">#</th>
                      \(setlistColumnHeader)
                      <th class="px-4 py-3 text-left sortable cursor-pointer select-none" data-col="title">Title <span class="sort-icon"></span></th>
                      <th class="px-4 py-3 text-left sortable cursor-pointer select-none" data-col="artist">Artist <span class="sort-icon"></span></th>
                      <th class="px-4 py-3 text-left sortable cursor-pointer select-none" data-col="genre">Genre <span class="sort-icon"></span></th>
                      <th class="px-4 py-3 text-center sortable cursor-pointer select-none" data-col="year">Year <span class="sort-icon"></span></th>
                      <th class="px-4 py-3 text-center sortable cursor-pointer select-none" data-col="duration">Duration <span class="sort-icon"></span></th>
                      <th class="px-4 py-3 text-center">Played</th>
                    </tr>
                  </thead>
                  <tbody id="trackBody"></tbody>
                </table>
                <div id="noResults" class="hidden py-10 text-center text-slate-500 text-sm">No tracks match your filter.</div>
              </div>
            </section>

          </div>

          <script>
            // ── Data ────────────────────────────────────────────────
            const isMulti = \(isMulti ? "true" : "false");
            const rows = \(tableJSON);

            // Lowercase + strip diacritics for accent-insensitive search
            function norm(s) {
              return String(s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
            }

            // ── Render table ─────────────────────────────────────────
            const tbody = document.getElementById('trackBody');
            rows.forEach((r, i) => {
              const tr = document.createElement('tr');
              tr.className = 'border-b border-slate-700/60 hover:bg-slate-700/30 transition-colors';
              tr.dataset.title = norm(r.title);
              tr.dataset.artist = norm(r.artist);
              tr.dataset.genre = norm(r.genre);
              tr.dataset.year = r.year;
              tr.dataset.setlist = norm(r.setlist);
              tr.dataset.duration = r.duration;
              const setlistCell = isMulti ? `<td class="px-4 py-2 text-teal-400 max-w-[140px] truncate" title="${esc(r.setlist)}">${esc(r.setlist)}</td>` : '';
              const played = r.played
                ? '<span class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-teal-500/20 text-teal-400 text-xs">✓</span>'
                : '';
              tr.innerHTML = `
                <td class="px-4 py-2 text-slate-500 tabular-nums">${i + 1}</td>
                ${setlistCell}
                <td class="px-4 py-2 font-medium text-white max-w-[200px] truncate" title="${esc(r.title)}">${esc(r.title)}</td>
                <td class="px-4 py-2 max-w-[160px] truncate" title="${esc(r.artist)}">${esc(r.artist)}</td>
                <td class="px-4 py-2"><span class="genre-tag">${esc(r.genre)}</span></td>
                <td class="px-4 py-2 text-center tabular-nums text-slate-400">${esc(r.year)}</td>
                <td class="px-4 py-2 text-center tabular-nums text-slate-400">${esc(r.duration)}</td>
                <td class="px-4 py-2 text-center">${played}</td>
              `;
              tbody.appendChild(tr);
            });

            function esc(s) {
              return String(s)
                .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
                .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
            }

            // ── Filter ───────────────────────────────────────────────
            document.getElementById('trackSearch').addEventListener('input', function() {
              const q = norm(this.value.trim());
              let visible = 0;
              tbody.querySelectorAll('tr').forEach(tr => {
                const match = !q ||
                  tr.dataset.title.includes(q) ||
                  tr.dataset.artist.includes(q) ||
                  tr.dataset.genre.includes(q) ||
                  tr.dataset.year.includes(q) ||
                  tr.dataset.setlist.includes(q);
                tr.classList.toggle('hidden', !match);
                if (match) visible++;
              });
              document.getElementById('noResults').classList.toggle('hidden', visible > 0);
            });

            // ── Sort ─────────────────────────────────────────────────
            let sortCol = null, sortDir = 1;
            document.querySelectorAll('.sortable').forEach(th => {
              th.addEventListener('click', () => {
                const col = th.dataset.col;
                if (sortCol === col) { sortDir *= -1; } else { sortCol = col; sortDir = 1; }
                document.querySelectorAll('.sortable').forEach(h => {
                  h.querySelector('.sort-icon').className = 'sort-icon';
                });
                th.querySelector('.sort-icon').className = 'sort-icon ' + (sortDir === 1 ? 'sort-asc' : 'sort-desc');
                const trs = Array.from(tbody.querySelectorAll('tr'));
                trs.sort((a, b) => {
                  const av = a.dataset[col] || '', bv = b.dataset[col] || '';
                  const an = parseFloat(av), bn = parseFloat(bv);
                  if (!isNaN(an) && !isNaN(bn)) return (an - bn) * sortDir;
                  return av.localeCompare(bv) * sortDir;
                });
                trs.forEach(tr => tbody.appendChild(tr));
              });
            });

            // ── Chart palette ────────────────────────────────────────
            const palette = [
              '#14b8a6','#f59e0b','#3b82f6','#ec4899','#8b5cf6',
              '#10b981','#f97316','#06b6d4','#84cc16','#e11d48'
            ];

            Chart.defaults.color = '#94a3b8';
            Chart.defaults.borderColor = '#334155';

            // Genre doughnut
            new Chart(document.getElementById('genreChart'), {
              type: 'doughnut',
              data: {
                labels: \(genreLabels),
                datasets: [{ data: \(genreValues), backgroundColor: palette, borderWidth: 2, borderColor: '#1e293b' }]
              },
              options: {
                responsive: true, maintainAspectRatio: false,
                plugins: {
                  legend: { position: 'right', labels: { boxWidth: 10, padding: 10, font: { size: 11 } } }
                }
              }
            });

            // Year bar
            new Chart(document.getElementById('yearChart'), {
              type: 'bar',
              data: {
                labels: \(yearLabels),
                datasets: [{ label: 'Tracks', data: \(yearValues), backgroundColor: '#14b8a6', borderRadius: 4 }]
              },
              options: {
                responsive: true, maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                  x: { grid: { display: false }, ticks: { maxRotation: 45, font: { size: 10 } } },
                  y: { beginAtZero: true, ticks: { precision: 0 } }
                }
              }
            });

            // Top artists horizontal bar
            new Chart(document.getElementById('artistChart'), {
              type: 'bar',
              data: {
                labels: \(artistLabels),
                datasets: [{ label: 'Tracks', data: \(artistValues), backgroundColor: palette.slice(0, \(min(10, artistCounts.count))), borderRadius: 4 }]
              },
              options: {
                indexAxis: 'y',
                responsive: true, maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                  x: { beginAtZero: true, ticks: { precision: 0 } },
                  y: { grid: { display: false }, ticks: { font: { size: 11 } } }
                }
              }
            });

            // ── Breakdown by Genre ────────────────────────────────────
            const statGenreLabels = \(statGenreLabelsJSON);
            const genresWithYears  = \(genresWithYearsJSON);
            const genreArtistDatasets = \(genreArtistDatasetsJSON);
            const genreYearRanges  = \(genreYearRangesJSON);
            const genreTimeMinutes = \(genreTimeMinutesJSON);
            const genreTimeFormatted = \(genreTimeFormattedJSON);

            if (statGenreLabels.length > 0) {
              // Top Artists by Genre — stacked horizontal bar
              new Chart(document.getElementById('artistByGenreChart'), {
                type: 'bar',
                data: { labels: statGenreLabels, datasets: genreArtistDatasets },
                options: {
                  indexAxis: 'y',
                  responsive: true, maintainAspectRatio: false,
                  plugins: {
                    legend: { position: 'bottom', labels: { boxWidth: 10, padding: 8, font: { size: 10 } } }
                  },
                  scales: {
                    x: { stacked: true, beginAtZero: true, ticks: { precision: 0 } },
                    y: { stacked: true, grid: { display: false } }
                  }
                }
              });

              // Year Range by Genre — floating horizontal bar
              if (genresWithYears.length > 0) {
                new Chart(document.getElementById('yearRangeChart'), {
                  type: 'bar',
                  data: {
                    labels: genresWithYears,
                    datasets: [{
                      label: 'Year Range',
                      data: genreYearRanges,
                      backgroundColor: palette.slice(0, genresWithYears.length),
                      borderRadius: 4
                    }]
                  },
                  options: {
                    indexAxis: 'y',
                    responsive: true, maintainAspectRatio: false,
                    plugins: { legend: { display: false } },
                    scales: {
                      x: { min: 1900, ticks: { precision: 0, callback: v => Math.round(v) } },
                      y: { grid: { display: false } }
                    }
                  }
                });
              }

              // Time Played by Genre — horizontal bar (minutes on axis, formatted in tooltip)
              new Chart(document.getElementById('timeByGenreChart'), {
                type: 'bar',
                data: {
                  labels: statGenreLabels,
                  datasets: [{
                    label: 'Duration',
                    data: genreTimeMinutes,
                    backgroundColor: palette.slice(0, statGenreLabels.length),
                    borderRadius: 4
                  }]
                },
                options: {
                  indexAxis: 'y',
                  responsive: true, maintainAspectRatio: false,
                  plugins: {
                    legend: { display: false },
                    tooltip: {
                      callbacks: {
                        label: ctx => ' ' + genreTimeFormatted[ctx.dataIndex]
                      }
                    }
                  },
                  scales: {
                    x: { beginAtZero: true, ticks: { callback: v => v + 'm' } },
                    y: { grid: { display: false } }
                  }
                }
              });
            }
          </script>
        </body>
        </html>
        """
    }

    // MARK: - Helpers

    private static func card(_ label: String, _ value: String) -> String {
        """
        <div class="bg-slate-800 rounded-xl p-4 border border-slate-700">
          <div class="text-xs text-slate-500 uppercase tracking-wide mb-1">\(htmlEscape(label))</div>
          <div class="text-2xl font-bold text-teal-400">\(htmlEscape(value))</div>
        </div>
        """
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private static func htmlEscape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func jsonString(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }
}

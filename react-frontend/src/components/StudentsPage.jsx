import { useState, useEffect } from 'react';

const SPREADSHEET_URL = 'https://docs.google.com/spreadsheets/d/1hODzl2TYkFZCRi7GOhkF5XbQgU0a__Tun8LYdegIaBk/edit?gid=625149784#gid=625149784';

export default function StudentsPage({ showToast }) {
  const [students, setStudents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [syncingOnclass, setSyncingOnclass] = useState(false);
  const [search, setSearch] = useState('');

  useEffect(() => { loadStudents(); }, []);

  async function loadStudents() {
    setLoading(true);
    try {
      const res = await fetch('/api/onclass/students_list');
      const data = await res.json();
      setStudents(data.students || []);
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      setLoading(false);
    }
  }

  async function handleSyncOnclass() {
    setSyncingOnclass(true);
    try {
      const res = await fetch('/api/onclass/students?refresh=true');
      const data = await res.json();
      if (data.error) {
        showToast(`同期エラー: ${data.error}`, 'error');
      } else {
        showToast(`オンクラスから${data.students.length}名を同期しました`, 'success');
        await loadStudents();
      }
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      setSyncingOnclass(false);
    }
  }

  async function handleSync() {
    setSyncing(true);
    try {
      const res = await fetch('/api/onclass/sync_sidekiq', { method: 'POST' });
      const data = await res.json();
      if (data.ok) {
        showToast('スプシ同期ジョブを一括実行しました。反映まで数分かかります。', 'success');
      } else {
        showToast(data.error || '同期に失敗しました', 'error');
      }
    } catch (e) {
      showToast(e.message, 'error');
    } finally {
      setSyncing(false);
    }
  }

  async function handleDelete(student) {
    try {
      const res = await fetch(`/api/onclass/students/${student.id}`, { method: 'DELETE' });
      if (res.ok) {
        setStudents(prev => prev.filter(s => s.id !== student.id));
        showToast(`${student.name} を削除しました（ローカルのみ）`, 'success');
      } else {
        const data = await res.json();
        showToast(data.error || '削除に失敗しました', 'error');
      }
    } catch (e) {
      showToast(e.message, 'error');
    }
  }

  // コース別にグループ化
  const filtered = search
    ? students.filter((s) => s.name.includes(search) || s.course.includes(search))
    : students;

  const filteredByCourse = {};
  filtered.forEach((s) => {
    if (!filteredByCourse[s.course]) filteredByCourse[s.course] = [];
    filteredByCourse[s.course].push(s);
  });

  return (
    <div className="students-page">
      {/* ヘッダー */}
      <div className="students-header">
        <h2 className="students-title">受講生一覧</h2>
        <div className="students-actions">
          <button
            className="btn-action btn-onclass"
            onClick={handleSyncOnclass}
            disabled={syncingOnclass}
          >
            {syncingOnclass ? '⏳ 取得中...' : '🔄 オンクラスと同期'}
          </button>
          <a
            href={SPREADSHEET_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="btn-action btn-spreadsheet"
          >
            📊 スプレッドシート
          </a>
          <button
            className="btn-action btn-sidekiq"
            onClick={handleSync}
            disabled={syncing}
          >
            {syncing ? '⏳ 同期中...' : '⚡ スプシ同期'}
          </button>
        </div>
      </div>

      {/* 検索 + 統計 */}
      <div className="students-toolbar">
        <div className="students-search-wrap">
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="名前・コースで検索..."
            className="students-search"
          />
          {search && (
            <button className="students-search-clear" onClick={() => setSearch('')}>✕</button>
          )}
        </div>
        <div className="students-stats">
          <span className="stat-badge stat-total">{filtered.length}名</span>
          {Object.entries(filteredByCourse).map(([course, list]) => (
            <span key={course} className="stat-badge stat-course">
              {course.replace('コース', '')}: {list.length}
            </span>
          ))}
        </div>
      </div>

      {/* 一覧 */}
      {loading ? (
        <div className="students-loading">
          <span className="spinner" /> 読み込み中...
        </div>
      ) : filtered.length === 0 ? (
        <div className="students-empty">
          {search ? '該当する受講生が見つかりません' : '受講生データがありません。「オンクラスと同期」で取得してください。'}
        </div>
      ) : (
        Object.entries(filteredByCourse).map(([course, list]) => (
          <div key={course} className="students-course-group">
            <h3 className="course-heading">{course}（{list.length}名）</h3>
            <div className="students-grid">
              {list.map((s) => (
                <div key={s.id} className="student-card">
                  <span className="student-name">{s.name}</span>
                  <button
                    className="student-delete"
                    onClick={() => handleDelete(s)}
                    title="ローカルから削除（オンクラスには影響なし）"
                  >
                    ✕
                  </button>
                </div>
              ))}
            </div>
          </div>
        ))
      )}

      {/* フッター */}
      {students.length > 0 && (
        <div className="students-footer">
          最終取得: {students[0]?.fetchedAt ? new Date(students[0].fetchedAt).toLocaleString('ja-JP') : '不明'}
          ・{students.length}名登録
        </div>
      )}
    </div>
  );
}

import { useState, useEffect } from 'react';
import { syncOnclassStudents } from '../api.js';

const SPREADSHEET_URL = 'https://docs.google.com/spreadsheets/d/1hODzl2TYkFZCRi7GOhkF5XbQgU0a__Tun8LYdegIaBk/edit?gid=625149784#gid=625149784';

export default function StudentsPage({ showToast }) {
  const [students, setStudents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [syncingOnclass, setSyncingOnclass] = useState(false);
  const [syncLog, setSyncLog] = useState('');
  const [search, setSearch] = useState('');
  const [activeTab, setActiveTab] = useState('all');

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
    setSyncLog('同期開始...');
    try {
      await syncOnclassStudents((event) => {
        if (event.type === 'log') {
          setSyncLog(event.message);
          showToast(event.message, 'info');
        } else if (event.type === 'done') {
          setSyncLog('');
          showToast(event.message, 'success');
          loadStudents();
        } else if (event.type === 'error') {
          setSyncLog('');
          showToast(event.message, 'error');
        }
      });
    } catch (e) {
      showToast(e.message, 'error');
      setSyncLog('');
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

  // コース一覧を取得
  const courses = [...new Set(students.map(s => s.course))].sort();

  // 検索フィルタ
  const filtered = search
    ? students.filter((s) => s.name.includes(search) || s.course.includes(search))
    : students;

  // タブでフィルタ
  const displayed = activeTab === 'all'
    ? filtered
    : filtered.filter(s => s.course === activeTab);

  // 表示用のコース別グループ
  const displayedByCourse = {};
  displayed.forEach((s) => {
    if (!displayedByCourse[s.course]) displayedByCourse[s.course] = [];
    displayedByCourse[s.course].push(s);
  });

  // コース別の人数（検索フィルタ適用後）
  const countByCourse = {};
  filtered.forEach((s) => {
    countByCourse[s.course] = (countByCourse[s.course] || 0) + 1;
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

      {/* 同期進捗 */}
      {syncingOnclass && syncLog && (
        <div className="students-sync-progress">
          <span className="spinner" style={{ width: 14, height: 14 }} /> {syncLog}
        </div>
      )}

      {/* タブ */}
      <div className="students-tabs">
        <button
          className={`students-tab ${activeTab === 'all' ? 'active' : ''}`}
          onClick={() => setActiveTab('all')}
        >
          全て ({filtered.length})
        </button>
        {courses.map(course => (
          <button
            key={course}
            className={`students-tab ${activeTab === course ? 'active' : ''}`}
            onClick={() => setActiveTab(course)}
          >
            {course.replace('コース', '')} ({countByCourse[course] || 0})
          </button>
        ))}
      </div>

      {/* 検索 */}
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
        <span className="stat-badge stat-total">{displayed.length}名表示</span>
      </div>

      {/* 一覧 */}
      {loading ? (
        <div className="students-loading">
          <span className="spinner" /> 読み込み中...
        </div>
      ) : displayed.length === 0 ? (
        <div className="students-empty">
          {search ? '該当する受講生が見つかりません' : '受講生データがありません。「オンクラスと同期」で取得してください。'}
        </div>
      ) : (
        Object.entries(displayedByCourse).map(([course, list]) => (
          <div key={course} className="students-course-group">
            {activeTab === 'all' && (
              <h3 className="course-heading">{course}（{list.length}名）</h3>
            )}
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

# 清理测试数据：只保留预置账号，清空其进度
import json
import os
import sqlite3

DB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "server", "data.db")
con = sqlite3.connect(DB)
con.execute("PRAGMA journal_mode=WAL")

before = con.execute("SELECT code FROM users").fetchall()
con.execute("DELETE FROM state WHERE code NOT IN ('陈禹竹')")
con.execute("DELETE FROM users WHERE code NOT IN ('陈禹竹')")
con.execute("UPDATE state SET json='{}', rev=0 WHERE code='陈禹竹'")
con.execute("UPDATE users SET wx_openid=NULL WHERE code='陈禹竹'")
con.commit()

users = con.execute("SELECT code, (pass_hash IS NOT NULL) FROM users").fetchall()
states = con.execute("SELECT code, json, rev FROM state").fetchall()
print("清理前账号:", [r[0] for r in before])
print("现有账号:", users)
print("现有进度:", states)
con.close()
